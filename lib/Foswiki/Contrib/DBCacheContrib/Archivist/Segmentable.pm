#
# Copyright (C) 2013-2014 Michael Daum http://michaeldaumconsulting.com
#
package Foswiki::Contrib::DBCacheContrib::Archivist::Segmentable;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::MemArchivist ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::MemArchivist');

use Foswiki::Contrib::DBCacheContrib::SegmentMap ();

use Storable ();

sub new {
    my ( $class, $cacheName, $segmentsImpl ) = @_;

    my $workDir = Foswiki::Func::getWorkArea('DBCacheContrib') . '/segments';

    $cacheName =~ s/\//\./go;

    my $this = bless(
        {
            _segmentsDir  => $workDir . '/' . $cacheName,
            _segmentsImpl => $segmentsImpl
              || 'Foswiki::Contrib::DBCacheContrib::MemMap',
        },
        $class
    );

    mkdir $workDir unless -d $workDir;
    mkdir $this->{_segmentsDir} unless -d $this->{_segmentsDir};

    return $this;
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

sub sync {
    my $this = shift;

    return unless $this->{root};

    $this->{root}->setArchivist(undef);

    foreach my $seg ( $this->{root}->getSegments() ) {
        if ( !defined( $seg->{_modified} ) || $seg->{_modified} ) {
            my $segmentFile = $this->_getCacheFileOfSegment($seg);

            #print STDERR "storing segment $seg->{id}\n";
            $seg->{_modified} = 0;
            Storable::lock_store( $seg, $segmentFile );
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
            my $seg = Storable::lock_retrieve($cacheFile);

            #print STDERR "loading segment $seg->{id}\n";
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

        foreach $seg ( $this->{root}->getSegments() ) {
            if ( !defined( $seg->{_modified} ) || $seg->{_modified} ) {

                #print STDERR "updating cache_time of segment $seg->{id}\n";
                $seg->{'.cache_time'} = time();
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

    my $file = $this->_getCacheFileOfSegment($seg) if defined $seg;

    my $time = $this->_getModificationTime($file);

#print STDERR "cache_time-time=".($seg->{'.cache_time'} - $time)."\n" if defined $seg->{'.cache_time'};

    return 1
      if $time == 0
      || !defined( $seg->{'.cache_time'} )
      || $seg->{'.cache_time'} < $time;

    return 0;
}

sub _getModificationTime {
    my ( $this, $cacheFile ) = @_;

    return 0 unless $cacheFile;
    my @stat = stat($cacheFile);

    return $stat[9] || $stat[10] || 0;
}

sub _getCacheFileOfSegment {
    my ( $this, $seg ) = @_;

    die "segment has got no id" unless defined $seg->{id};

    return $this->{_segmentsDir} . '/data_' . $seg->{id};
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

