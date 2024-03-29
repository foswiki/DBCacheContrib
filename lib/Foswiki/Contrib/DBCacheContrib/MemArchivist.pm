# See bottom of file for license and copyright information

# Package-private base class that implements Archivist for in-memory
# representation of data It is subclassed by the Storable and File archivists.

package Foswiki::Contrib::DBCacheContrib::MemArchivist;
use strict;
use warnings;

use Assert;
use Foswiki::Contrib::DBCacheContrib::MemMap    ();
use Foswiki::Contrib::DBCacheContrib::MemArray  ();
use Foswiki::Contrib::DBCacheContrib::Archivist ();

our @ISA = ('Foswiki::Contrib::DBCacheContrib::Archivist');

sub new {
    my ($class) = @_;

    my $this = bless( {}, $class );
    return $this;
}

# Factory for new Map objects
sub newMap {
    my $this = shift;
    return new Foswiki::Contrib::DBCacheContrib::MemMap(@_);
}

# Factory for new Array objects
sub newArray {
    my $this = shift;
    return new Foswiki::Contrib::DBCacheContrib::MemArray(@_);
}

# Subclasses must provide getRoot and clear.

1;
__END__

Copyright (C) 2004-2022 Crawford Currie, http://c-dot.co.uk and Foswiki Contributors
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
