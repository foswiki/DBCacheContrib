#
# Copyright (C) 2007-2017 Crawford Currie, http://c-dot.co.uk
#
package Foswiki::Contrib::DBCacheContrib::Archivist::Storable;
use strict;

use Foswiki::Contrib::DBCacheContrib::MemArchivist ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::MemArchivist');

use Storable ();

sub new {
    my $class     = shift;
    my $cacheName = shift;

    my $this = bless( $class->SUPER::new(@_), $class );

    my $workDir = Foswiki::Func::getWorkArea('DBCacheContrib');
    $cacheName =~ s/\//\./go;

    $this->{_file} = $workDir . '/' . $cacheName;

    return $this;
}

sub isModified {
    my $this = shift;

    my $time = $this->_getModificationTime();

    return 1
      if $time == 0
      || !defined( $this->{root} )
      || !defined( $this->{root}{'.cache_time'} )
      || $this->{root}{'.cache_time'} < $time;

    return 0;

}

sub _getModificationTime {
    my $this = shift;

    my $filename = $this->_getCacheFile();
    return 0 unless $filename;
    my @stat = stat($filename);

    return $stat[9] || $stat[10] || 0;
}

sub _getCacheFile {
    my $this = shift;

    my $cacheFile = $this->{_file};
    return $cacheFile if defined $cacheFile && -f $cacheFile;

    return;
}

sub updateCacheTime {
    my ( $this, $root ) = @_;

    $root ||= $this->{root};
    return unless defined $root;

    #print STDERR "updating cache_time\n";
    $root->{'.cache_time'} = time();
}

sub clear {
    my $this = shift;

    #print STDERR "clearing, deleting $this->{_file}\n";
    unlink( $this->{_file} );
    undef $this->{root};
}

sub DESTROY {
    my $this = shift;
    undef $this->{root};
}

sub sync {
    my $this = shift;

    #my ($package, $filename, $line) = caller(2);
    #print STDERR "called sync $this->{_file} from $package, $line\n";

    # Clear the archivist to avoid having pointers in the Storable
    $this->{root}->setArchivist(undef) if $this->{root};

    my $root = $this->getRoot();

    #print STDERR "storing to $this->{_file}\n";

    Storable::lock_store( $root, $this->{_file} );
    $this->{root}->setArchivist($this) if $this->{root};
}

sub getRoot {
    my ($this) = @_;

    my $root = $this->{root};
    unless ($root) {
        if ( -e $this->{_file} ) {
            $root = $this->{root} = Storable::lock_retrieve( $this->{_file} );

            #print STDERR "loaded from $this->{_file}\n";
            $root->setArchivist($this);
        }
        else {
            $root = $this->{root} = $this->newMap();
        }

        # remember the time the file has been loaded
        $this->updateCacheTime($root);

    }
    return $root;
}

1;
