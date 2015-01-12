#
# Copyright (C) 2013-2015 Michael Daum http://michaeldaumconsulting.com
#
package Foswiki::Contrib::DBCacheContrib::Archivist::Segmentable;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::Archivist::Serializable ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::Archivist::Serializable');

use Storable ();

sub serialize {
    my ( $this, $seg ) = @_;

    my $segmentFile = $this->_getCacheFileOfSegment($seg);
    Storable::lock_store( $seg, $segmentFile );
}

sub deserialize {
    my ( $this, $file ) = @_;

    return Storable::lock_retrieve($file);
}

1;

