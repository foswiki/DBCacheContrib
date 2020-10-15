package DBCacheContribTestCase;

use strict;
use warnings;

use FoswikiFnTestCase;
our @ISA = qw( FoswikiFnTestCase );

use Assert;
use File::Temp;
use Devel::Cycle;

use Foswiki::Contrib::DBCacheContrib::Archivist::Storable;
use Foswiki::Contrib::DBCacheContrib::Archivist::BDB;
use Foswiki::Contrib::DBCacheContrib::Archivist::Segmentable;

sub set_up {
    my $this = shift;
    $this->SUPER::set_up();
}

sub tear_down {
    my $this = shift;

    Devel::Cycle::find_cycle( $this->{ar} ) if $this->{ar};

    # Clear out any existing data from the archive
    $this->{ar}->clear() if $this->{ar};

    $this->SUPER::tear_down();

    unlink( $this->{tempfn} ) if $this->{tempfn};
}

sub setArchivist {
    my ( $this, $archivist ) = @_;
    $this->{archivist} = $archivist;
    $this->{tempfn}    = File::Temp::tmpnam();
    $this->{ar}        = $archivist->new( $this->{tempfn} );
}

sub StorableArchivist {
    my $this = shift;
    $this->setArchivist(
        'Foswiki::Contrib::DBCacheContrib::Archivist::Storable');
}

sub SegmentArchivist {
    my $this = shift;
    $this->setArchivist(
        'Foswiki::Contrib::DBCacheContrib::Archivist::Segmentable');
}

our $bdb;

{

    package DBCacheContribTestCase::FakeArchivist;

    sub new {
        $bdb->{stubs} = {};
        return $bdb;
    }
};

sub BDBArchivist {
    my $this = shift;
    if ( !$bdb ) {
        $this->setArchivist('Foswiki::Contrib::DBCacheContrib::Archivist::BDB');
        $bdb = $this->{ar};
    }
    else {
        $this->{ar}   = $bdb;
        $bdb->{stubs} = {};
    }
    $this->{archivist} = 'DBCacheContribTestCase::FakeArchivist';
}

sub fixture_groups {
    return (
        [
            #'StorableArchivist',
            'SegmentArchivist',

            # SMELL: out of order
            #'BDBArchivist'
        ]
    );
}

1;
