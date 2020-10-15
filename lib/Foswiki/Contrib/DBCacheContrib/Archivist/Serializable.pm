#
# Copyright (C) 2013-2020 Foswiki Contributors
#

# abstract class servig as a common base for Segmentable and Sereal archivist
# only two methods required to implement are serialize() and deserialize()

package Foswiki::Contrib::DBCacheContrib::Archivist::Serializable;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::MemArchivist ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::MemArchivist');

use Foswiki::Contrib::DBCacheContrib::SegmentMap ();

sub new {
    my ( $class, $cacheName, $segmentsImpl ) = @_;

    $cacheName =~ s/\//\./go;

    my $this = bless(
        {
            _cacheName    => $cacheName,
            _segmentsImpl => $segmentsImpl
              || 'Foswiki::Contrib::DBCacheContrib::MemMap',
        },
        $class
    );

    $this->init;

    return $this;
}

sub init {
    my $this = shift;

    my $workDir = Foswiki::Func::getWorkArea('DBCacheContrib') . '/segments';
    $this->{_segmentsDir} = $workDir . '/' . $this->{_cacheName};

    mkdir $workDir unless -d $workDir;
    mkdir $this->{_segmentsDir} unless -d $this->{_segmentsDir};
}

sub clear {
    my $this = shift;

    if ( $this->{root} ) {
        foreach my $seg ( $this->{root}->getSegments() ) {
            my $file = $this->_getCacheFileOfSegment($seg);

            #print STDERR "deleting $file\n";
            unlink($file);
        }
    }

    undef $this->{root};
}

sub DESTROY {
    my $this = shift;

    undef $this->{root};
}

sub serialize {
    my ( $this, $data ) = @_;

    die "serializer not implemented";
}

sub deserialize {
    my ( $this, $file ) = @_;

    my $data;

    die "deserializer not implemented";

    return $data;
}

sub sync {
    my $this = shift;

    return unless $this->{root};

    $this->{root}->setArchivist(undef);

    foreach my $seg ( $this->{root}->getSegments() ) {
        if ( !defined( $seg->{_modified} ) || $seg->{_modified} ) {

            #print STDERR "storing segment $seg->{id}\n";
            $seg->{_modified} = 0;
            $this->serialize($seg);
            $this->updateCacheTime($seg);
        }
        else {
            #print STDERR "segment $seg->{id} not modified\n";
        }
    }

    $this->{root}->setArchivist($this) if $this->{root};
}

sub getRoot {
    my $this = shift;

    unless ( $this->{root} ) {
        $this->{root} = new Foswiki::Contrib::DBCacheContrib::SegmentMap(
            $this->{_segmentsImpl} );
        $this->{root}->setArchivist($this);

        foreach my $cacheFile ( $this->_getCacheFiles ) {
            my $seg = $this->deserialize($cacheFile);

           #print STDERR "loading segment $seg->{id} for $this->{_cacheName}\n";
            $this->{root}->addSegment($seg);

            # remember the time the file has been loaded
            $this->updateCacheTime($seg);
        }
    }

    return $this->{root};
}

sub updateCacheTime {
    my ( $this, $seg ) = @_;

    if ( defined $seg ) {

        #print STDERR "updating cache_time of segment $seg->{id}\n";

        $seg->{'.cache_time'} = time();

    }
    else {

        foreach my $s ( $this->{root}->getSegments() ) {
            if ( !defined( $s->{_modified} ) || $s->{_modified} ) {

                #print STDERR "updating cache_time of segment $s->{id}\n";
                $s->{'.cache_time'} = time();
            }
        }
    }
}

sub isModified {
    my $this = shift;

    return 1 if !defined( $this->{root} );

    foreach my $seg ( $this->{root}->getSegments() ) {
        return 1 if $this->isModifiedSegment($seg);
    }

    return 0;
}

sub isModifiedSegment {
    my ( $this, $seg ) = @_;

    my $time = $this->_getModificationTime($seg);

    return 1
      if $time == 0
      || !defined( $seg->{'.cache_time'} )
      || $seg->{'.cache_time'} < $time;

    return 0;
}

sub _getModificationTime {
    my ( $this, $seg ) = @_;

    return 0 unless $seg;

    my $file = $this->_getCacheFileOfSegment($seg);
    return 0 unless $file;

    my @stat = stat($file);
    return $stat[9] || $stat[10] || 0;
}

sub _getCacheFileOfSegment {
    my ( $this, $seg ) = @_;

    die "segment has got no id" unless defined $seg->{id};

    # untaint
    $seg->{id} =~ /^(.*)$/s;
    my $id = $1;

    return $this->{_segmentsDir} . '/data_' . $id;
}

sub _getCacheFiles {
    my $this = shift;

    opendir( my $dh, $this->{_segmentsDir} )
      || die "can't opendir $this->{_segmentsDir}: $!";

    my @cacheFiles =
      sort map { $this->{_segmentsDir} . '/' . $_ }
      grep     { !/^\./ } readdir($dh);
    closedir $dh;

    return @cacheFiles;
}

1;
