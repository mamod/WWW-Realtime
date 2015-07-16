package RealTime;
use strict;
use warnings;
use Digest::MD5 qw( md5_hex );
use Time::HiRes qw( gettimeofday );
use Carp;
use HTTP::Tiny;
use Data::Dumper;
use bytes;
use URI;

sub _uniqid {
    my($s,$us) = gettimeofday();
    my $v = sprintf("%06d%010d%06d", $us, $s, $$);
    $v = md5_hex($v . rand(3));
    return $v;
}

sub new {
    my $class = shift;
    my $args = shift;
    my $self = bless {}, $class;

    croak "application key Required" if !$args->{application_key};
    croak "private key Required" if !$args->{private_key};

    $self->{serverCheck} = 'https://ortc-developers.realtime.co/server/2.1'; 
    $self->{AK}   = $args->{application_key};
    $self->{PK}   = $args->{private_key};
    $self->{http} =  HTTP::Tiny->new();
    $self->{uri}  = URI->new();
    return $self;
}

sub _checkServer {
    my $self = shift;
    my $result = $self->{http}->get($self->{serverCheck}, {
        appkey => $self->{AK}
    });

    if ($result->{success}){
        my $content = $result->{content};
        $content =~ m/"(.*?)"/;
        my $url = $1;
        return $url;
    }

    return;
}

sub uri_encode {
    return '' if !defined $_[0];
    $_[0] =~ s/([^A-Za-z0-9])/sprintf("%%%02X", ord($1))/seg;
    return $_[0];
}

sub _query {
    my $params = shift;
    my @params;
    while (my ($key, $value) = each(%{$params})) {
        push(@params, $key.'='.uri_encode($value));
    }

    return  join('&',@params);
}

sub send_message_part {
    my $self = shift;
    my $url = shift;
    my $channel = shift;
    my $msg = shift;

    my $params = {
        'AK' => $self->{AK},
        'PK' => $self->{PK},
        'C' => $channel,    
        'AT' => $self->{AT} || '12345678',
        'M' => $msg
    };

    $url = $url . '/send';

    my $response = $self->{http}->request('POST', $url, {
        content => _query( $params ),
        headers => { 'content-type' => 'application/x-www-form-urlencoded' }
    });

    print Dumper $response;
    return 1;
}

sub presence {
    my $self = shift;
    my $channel = shift;

    #http://ortc-developers2-euwest1-S0001.realtime.co/presence/enable/<appkey>/<channel>
    my $balance_url = $self->_checkServer();
    if (!$balance_url){ return; }
    my $url = $balance_url . '/presence/enable/' . $self->{AK} . '/' . $channel;

    my $params = {
        'privatekey' => $self->{PK},
        'metadata' => 1
    };

    my $response = $self->{http}->request('POST', $url, {
        content => _query( $params ),
        headers => { 'content-type' => 'application/x-www-form-urlencoded' }
    });

    return 1;
}

sub metadata {
    my $self = shift;
    my $channel = shift;

    my $balance_url = $self->_checkServer();
    if (!$balance_url){ return; }
    my $url = $balance_url . '/presence/' . $self->{AK} . '/P/' . $channel;
    my $response = $self->{http}->request('GET', $url);
    print Dumper $response;
    return $response;
}

sub publish {
    my $self = shift;
    my $options = shift;

    my $channel = $options->{channel};
    my $message = $options->{message};

    #get url
    my $balance_url = $self->_checkServer();
    if (!$balance_url){ return; }

    my $numberOfParts = int( bytes::length ($message) / 700 ) + 
                         (( bytes::length($message) % 700 == 0)? 0 : 1 );

    my $guid = substr(_uniqid(), 5, 8);

    my $part = 1;
    my $ret;
    while ($part <= $numberOfParts){
        $ret = $self->send_message_part($balance_url, $channel, 
                                          $guid . "_" . $part . "-" . $numberOfParts . "_" . 
                                          substr($message,($part-1) * 699, 699)
                                        ); #$response returned used for debug purposes
        return if !$ret;
        $part += 1;
    }

    return $ret;
}

1;

__END__
