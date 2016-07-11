#!/usr/bin/env perl

# Standard preamble
BEGIN {
    foreach my $pc ( split( /:/, $ENV{FOSWIKI_LIBS} ) ) {
        unshift @INC, $pc;
    }
}

use Foswiki::Contrib::Build;

package DBCacheBuild;

@DBCacheBuild::ISA = ("Foswiki::Contrib::Build");

sub new {
    my $class = shift;
    return bless( $class->SUPER::new("DBCacheContrib"), $class );
}

$build = new DBCacheBuild();

$build->build( $build->{target} );
