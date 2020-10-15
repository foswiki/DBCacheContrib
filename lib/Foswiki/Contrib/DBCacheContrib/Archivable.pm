# See bottom of file for license and copyright information

# Package-private mixin to add archivability to a collection object.

package Foswiki::Contrib::DBCacheContrib::Archivable;
use strict;
use Scalar::Util     ();
use Foswiki::Func    ();
use Foswiki::Form    ();
use Foswiki::Plugins ();

sub setArchivist {
    my $this      = shift;
    my $archivist = shift;
    my $done      = shift;

    $done ||= {};
    if ($archivist) {
        $this->{archivist} = $archivist;
        Scalar::Util::weaken( $this->{archivist} );
    }
    else {
        delete $this->{archivist};
    }
    $done->{$this} = 1;
}

sub getArchivist {
    my $this = shift;
    return $this->{archivist};
}

sub getDisplayValue {
    my ( $this, $name ) = @_;

    my $val      = $this->getFieldValue($name);
    my $fieldDef = $this->getFieldDef($name);
    return $val unless defined $fieldDef;

    $val = $fieldDef->getDefaultValue() if !defined($val) || $val eq '';

    if ( $fieldDef->can("getDisplayValue") ) {
        my $web   = $this->fastget("web");
        my $topic = $this->fastget("topic");
        $val = $fieldDef->getDisplayValue( $val, $web, $topic );
    }
    else {
        $val = $fieldDef->renderForDisplay( '$value(display)', $val );
    }

    return $val;
}

sub getFieldValue {
    my ( $this, $name ) = @_;

    # Only reference the hash if the contained form does not
    # define the field

    my $val;
    my $form = $this->getForm();
    $val = $form->fastget($name) if $form;
    $val = $this->fastget($name) unless defined $val;

    return $val;
}

sub getFieldDef {
    my ( $this, $name ) = @_;

    my $formDef = $this->getFormDef();
    return unless defined $formDef;
    return $formDef->getField($name);
}

sub getFormDef {
    my $this = shift;

    my $form = $this->getForm();
    return unless defined $form;

    my ( $formWeb, $formTopic ) =
      Foswiki::Func::normalizeWebTopicName( $this->fastget("web"),
        $form->fastget("name") );
    return new Foswiki::Form( $Foswiki::Plugins::SESSION, $formWeb,
        $formTopic );
}

sub getForm {
    my $this = shift;

    my $form = $this->fastget("form");
    $form = $this->fastget($form) if defined $form;

    return $form;
}

1;
__END__

Copyright (C) 2009-2020 Crawford Currie, http://c-dot.co.uk and Foswiki Contributors
and Foswiki Contributors. Foswiki Contributors are listed in the
AUTHORS file in the root of this distribution. NOTE: Please extend
that file, not this notice.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
