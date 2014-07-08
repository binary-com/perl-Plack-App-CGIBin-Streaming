package Plack::App::CGIBin::Streaming::Request;

use 5.014;
use strict;
use warnings;
no warnings 'uninitialized';
use Carp;

our @attr;

our $DEFAULT_CONTENT_TYPE='text/plain';
our $DEFAULT_MAX_BUFFER=8000;

BEGIN {
    @attr=(qw/env responder writer _buffer _buflen _headers max_buffer
              content_type filter_before filter_after on_status_output
              parse_headers _header_buffer status/);
    for (@attr) {
        my $attr=$_;
        no strict 'refs';
        *{__PACKAGE__.'::'.$attr}=sub : lvalue {
            my $I=$_[0];
            $I->{$attr}=$_[1] if @_>1;
            $I->{$attr};
        };
    }
}

sub new {
    my $class=shift;
    $class=ref($class) || $class;
    my $self=bless {
                    content_type=>$DEFAULT_CONTENT_TYPE,
                    max_buffer=>$DEFAULT_MAX_BUFFER,
                    filter_before=>sub{1},
                    filter_after=>sub{},
                    on_status_output=>sub{},
                    _headers=>[],
                    _buffer=>[],
                    _buflen=>0,
                    status=>200,
                   }, $class;

    for( my $i=0; $i<@_; $i+=2 ) {
        my $method=$_[$i];
        $self->$method($_[$i+1]);
    }

    return $self;
}

sub print_header {
    my $self = shift;

    croak "KEY => VALUE pairs expected" if @_%2;
    #warn "print_header @_";
    push @{$self->{_headers}}, @_;
}

sub print_content {
    my $self = shift;

    if ($self->{parse_headers}) {
        $self->{_header_buffer}.=join('', @_);
        while( $self->{_header_buffer}=~s/\A(\S+)[ \t]*:[ \t]*(.+?)\r?\n// ) {
            my ($hdr, $val)=($1, $2);
            if ($hdr=~/\Astatus\z/i) {
                $self->{status}=$val;
            } elsif ($hdr=~/\Acontent-type\z/i) {
                $self->{content_type}=$val;
            } else {
                $self->print_header($hdr, $val);
            }
        }
        if ($self->{_header_buffer}=~s/\A\r?\n//) {
            delete $self->{parse_headers}; # done
            $self->print_content(delete $self->{_header_buffer})
                if length $self->{_header_buffer};
        }
        return;
    }

    $self->{filter_before}->($self, \@_) or return;

    my $len = 0;
    $len += length $_ for @_;
    #warn "print_content: $len bytes written";
    push @{$self->{_buffer}}, @_;
    $len += $self->{_buflen};
    $self->{_buflen}=$len;

    $self->flush if $len > $self->{max_buffer};

    $self->filter_after->($self, \@_);
}

sub _status_out {
    my $self = shift;
    my $is_done = shift;
    #warn "_status_out";
    $self->print_header('Content-Type', $self->{content_type});
    $self->print_header('Content-Length', $self->{_buflen})
        if $is_done;
    $self->on_status_output->($self);

    # $self->print_header('X-Accel-Buffering', 'no')
    #     if $self->content_type =~ m!text/html!i;

    $self->{writer}=$self->{responder}->([$self->{status},
                                          $self->{_headers},
                                          $is_done ? $self->{_buffer}: ()]);
}

sub flush {
    my $self = shift;
    return 0 unless @{$self->{_buffer}};

    #warn "flush @_";
    $self->_status_out unless $self->{writer};

    $self->{writer}->write(join '', @{$self->{_buffer}});
    @{$self->{_buffer}}=();
    $self->{_buflen}=0;

    return 0;
}

sub finalize {
    my $self = shift;

    #warn "finalize";
    if ($self->{writer}) {
        $self->{writer}->write(join '', @{$self->{_buffer}});
        $self->{writer}->close;
    } else {
        $self->_status_out(1);
    }


    %$self=();
    bless $self, 'Plack::App::CGIBin::Streaming::Request::Demolished';

    #use Carp(); Carp::cluck
    #warn
    #    "finalize done";
}

sub method      { $_[0]->{env}->{REQUEST_METHOD} }
sub port        { $_[0]->{env}->{SERVER_PORT} }
sub user        { $_[0]->{env}->{REMOTE_USER} }
sub request_uri { $_[0]->{env}->{REQUEST_URI} }
sub path_info   { $_[0]->{env}->{PATH_INFO} }
sub path        { $_[0]->{env}->{PATH_INFO} || '/' }
sub script_name { $_[0]->{env}->{SCRIPT_NAME} }

package Plack::App::CGIBin::Streaming::Request::Demolished;
use strict;

sub AUTOLOAD {
    our $AUTOLOAD;
    die "Calling $AUTOLOAD on a demolished request.";
}

sub flush {}
sub finalize {}
sub DESTROY {}

1;
