#
# Copyright (C) 2014-2015 Michael Daum http://michaeldaumconsulting.com
#
package Foswiki::Contrib::DBCacheContrib::Archivist::Sereal;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::Archivist::Serializable ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::Archivist::Serializable');

use Sereal ();
use Fcntl qw(:flock);

sub init {
    my $this = shift;

    my $workDir = Foswiki::Func::getWorkArea('DBCacheContrib') . '/sereal';
    $this->{_segmentsDir} = $workDir . '/' . $this->{_cacheName};

    mkdir $workDir unless -d $workDir;
    mkdir $this->{_segmentsDir} unless -d $this->{_segmentsDir};

    $this->{encoder} = Sereal::Encoder->new( { no_shared_hashkeys => 1 } );

    $this->{decoder} = Sereal::Decoder->new();
}

sub DESTROY {
    my $this = shift;

    undef $this->{encoder};
    undef $this->{decoder};
    undef $this->{root};
}

sub serialize {
    my ( $this, $seg ) = @_;

    my $data = $this->{encoder}->encode($seg);
    my $file = $this->_getCacheFileOfSegment($seg);

    my $FILE;

    open( $FILE, '> :raw :bytes', $file )
      || die "Can't create file $file - $!\n";
    flock( $FILE, LOCK_EX ) || die "Can't get exclusive lock on $file: $!\n";
    truncate $FILE, 0;
    print $FILE $data;
    close($FILE);    # unlocking as well
}

sub deserialize {
    my ( $this, $file ) = @_;

    my $data;
    my $FILE;

    open( $FILE, '< :raw :bytes', $file ) || die "Can't read file $file - $!\n";
    flock( $FILE, LOCK_SH ) || die "Can't get shared lock on $file: $!";
    local $/ = undef;    # set to read to EOF
    $data = <$FILE>;
    close($FILE);        # unlocking as well

    return $this->{decoder}->decode($data);
}

1;

