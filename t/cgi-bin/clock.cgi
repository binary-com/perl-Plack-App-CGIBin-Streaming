#!/usr/bin/perl

use strict;
use warnings;

BEGIN {push @main::loaded, __FILE__}

$|=0;

my $boundary='The Final Frontier';
print <<"EOF";
Status: 200
Content-Type: multipart/x-mixed-replace;boundary="$boundary";

EOF

$boundary="--$boundary\n";

my $mpheader=<<'HEADER';
Content-type: text/html; charset=UTF-8;

HEADER

for(1..100) {
    print ($boundary, $mpheader,
           '<html><body><h1>'.localtime()."</h1></body></html>\n");
    $|=1; $|=0;
    sleep 1;
}

print ($boundary);
