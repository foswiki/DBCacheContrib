# See bottom of file for license and copyright information
package Foswiki::Contrib::DBCacheContrib::SegmentMap;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::Map ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::Map');

use Assert;
use constant SEGMENT_SIZE => 250;

# Package-private map object that stores hashes in memory. Used with
# a Segmentable archivist

sub new {
    my $class   = shift;
    my $segImpl = shift;
    my $this    = $class->SUPER::new(@_);

    eval "use $segImpl;";
    die $@ if $@;

    $this->{_segmentsImpl} = $segImpl;
    $this->{_segments}     = undef;
    $this->{_segmentOfKey} = undef;

    return $this;
}

sub DESTROY {
    my $this = shift;

    # prevent recursive destruction
    return if $this->{_destroying};
    $this->{_destroying} = 1;

    # destroy sub objects
    foreach my $seg ( $this->getSegments() ) {
        undef $seg;
    }

    $this->{_segments}     = undef;
    $this->{_segmentOfKey} = undef;
}

sub addSegment {
    my ( $this, $seg ) = @_;

    $this->{_segments}{ $seg->{id} } = $seg;
    $this->{_segmentOfKey}{$_} = $seg foreach $seg->getKeys();
    $this->{_lastSegment} = $seg
      unless $this->{_lastSegment} || $seg->size() >= SEGMENT_SIZE;
}

sub getSegments {
    my $this = shift;

    return () unless defined $this->{_segments};
    return values %{ $this->{_segments} };
}

sub getSegmentOfKey {
    return $_[0]->{_segmentOfKey}{ $_[1] };
}

sub findFreeSegment {
    my $this = shift;

    foreach my $seg ( $this->getSegments() ) {
        return $seg if $seg->size() < SEGMENT_SIZE;
    }

    # nope
    return;
}

sub getNextSegmentId {
    my $this = shift;

    return 1 unless defined $this->{_segments};

    # get max id
    my @ids =
      sort { $b <=> $a } map { $_->{id} } values %{ $this->{_segments} };
    return shift(@ids) + 1;
}

sub getSegment {
    my ( $this, $key ) = @_;

    my $seg = $this->getSegmentOfKey($key);
    return $seg if defined $seg;

    my $lastSegment = $this->{_lastSegment};
    if ( !defined $lastSegment
        || $lastSegment->size() >= SEGMENT_SIZE )
    {
        $lastSegment = $this->{_lastSegment} = $this->{_segmentsImpl}->new();
        $lastSegment->{id} = $this->getNextSegmentId();

        $this->addSegment($lastSegment);
    }

    return $lastSegment;
}

sub size {
    my $this = shift;

    my $size = 0;
    foreach my $seg ( $this->getSegments() ) {
        $size += scalar( $seg->getKeys() );
    }

    return $size;
}

sub getKeys {
    my $this = shift;

    my @keys = ();

    foreach my $seg ( $this->getSegments() ) {
        push @keys, $seg->getKeys();
    }

    return @keys;
}

sub getValues {
    my $this = shift;

    my @values = ();

    foreach my $seg ( $this->getSegments() ) {
        push @values, $seg->getValues();
    }

    return @values;
}

sub STORE {
    my ( $this, $key, $val ) = @_;
    my $seg = $this->getSegment($key);
    $seg->STORE( $key, $val );
    $this->{_segmentOfKey}{$key} = $seg;
    $seg->{_modified} = 1;
}

sub FETCH {
    my ( $this, $key ) = @_;
    my $seg = $this->getSegmentOfKey($key);
    return unless $seg;
    return $seg->FETCH($key);
}

sub FIRSTKEY {
    die "not implemented";
}

sub NEXTKEY {
    die "not implemented";
}

sub EXISTS {
    return $_[0]->getSegmentOfKey( $_[1] ) ? 1 : 0;
}

sub DELETE {
    my ( $this, $key ) = @_;
    my $seg = $this->getSegmentOfKey($key);
    return unless defined $seg;

    $seg->{_modified} = 1;
    delete $this->{_segmentOfKey}{$key};
    return $seg->DELETE($key);
}

sub CLEAR {
    my $this = shift;

    # explicitly destroy segments
    foreach my $seg ( $this->getSegments() ) {
        undef $seg;
    }

    $this->{_segments}     = undef;
    $this->{_segmentOfKey} = undef;
    $this->{_lastSegment}  = undef;
}

sub SCALAR {
    return $_[0]->size();
}

1;
__END__

Copyright (C) 2013-2017 Foswiki Contributors

and Foswiki Contributors. Foswiki Contributors are listed in the
AUTHORS file in the root of this distribution. NOTE: Please extend
that file, not this notice.

Additional copyrights apply to some or all of the code in this module
as follows:
   * Copyright (C) Motorola 2003 - All rights reserved

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.

