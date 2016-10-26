requires 'perl', '5.014';

requires 'Plack', '0.9989';
requires 'CGI::Compile', '0.17';
requires 'PerlIO::via', '0.11';
requires 'CGI', '4.33';
on test => sub {
    requires 'Test::More', '0.88';
    requires 'Starman', '0.3001';
    requires 'Devel::Cover',                    '1.23';
    requires 'Devel::Cover::Report::Codecov',   '0.14';
};
