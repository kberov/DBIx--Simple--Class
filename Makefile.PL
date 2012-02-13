use 5.010;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'DBIx::Simple::Class',
    AUTHOR              => q{Красимир Беров <berov@cpan.org>},
    VERSION_FROM        => 'lib/DBIx/Simple/Class.pm',
    ABSTRACT_FROM       => 'lib/DBIx/Simple/Class.pm',
    LICENSE             => 'perl',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'DBIx::Simple' => 1.33,
        'SQL::Abstract'=> 1.72,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'DBIx-Simple-Class-*' },
);
