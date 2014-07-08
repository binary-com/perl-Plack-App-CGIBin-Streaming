#!/usr/bin/perl

use strict;
use warnings;
use Plack::App::CGIBin::Streaming;

my $r=Plack::App::CGIBin::Streaming->request;

my @args=split /,/, $ENV{QUERY_STRING};

my $pc;
my $cl=1;
for (my $i=0; $i<@args; $i+=2) {
    my ($k, $v)=@args[$i, $i+1];

    for ($k) {
        /^status$/ and $r->status=$v, next;
        /^H$/ and $r->print_header(split /:/, $v), next;
        /^pc$/ and $r->print_header('pc', 1), $pc=1, next;
        /^cl$/ and $cl=$v, next;
        /^ct$/ and $r->content_type($v), next;
    }
}

if ($pc) {
    $r->print_content('x' x 100) for (1..int($cl/100));
    $r->print_content('x' x ($cl%100));
} else {
    print('x' x 100) for (1..int($cl/100));
    print('x' x ($cl%100));
}
