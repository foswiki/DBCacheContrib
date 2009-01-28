#
# Copyright (C) Motorola 2003 - All rights reserved
# Copyright (C) Crawford Currie 2004, 2009
#

=begin TML
---++ package Foswiki::Contrib::DBCacheContrib::Map

This is an interface that is implemented by all back-end stores
(archivists). A Map is basically a hash table, and indeed can be
tied to a perl hash.

Objects of this class are created using the =newMap= interface defined
by =Foswiki::Contrib::DBCacheContrib::Archivist=. You can use references
in the content of a Map, but you can only refer to other objects that
were created using the same Archivist. If you point anywhere else, expect
fireworks.

The keys in a map operate like any other keys, except that key names
beginning with underscore are interpreted as internal
references to objects that must be "weak" i.e. are not used in garbage
collection (see the doc on Scalar::Util::weaken for more info).
For example, DBCacheContrib defines '_up' and '_web' references
to improve tree traversal performance, but these references will be
regarded by the archivist as 'weak' so will be ignored during GC.

=cut

# Typically subclasses use an "archivist" handle to the underlying storage
# mechanism.
#
# Correctly written subclasses should be usable with tied hashes or
# as objects. For example, to create a new MemMap backed up by a simple
# disk file, use:
#    my $map = new Foswiki::Contrib::DBCacheContrib::MemMap();
# this can then be tied using
#    my %map;
#    tie (%map, 'Foswiki::Contrib::DBCacheContrib::MemMap', $map);
# You can also construct a new hash by simply passing undef in place of $map.
#
# Note that the Archivist class provides factories for new maps and hashes.
# You are recommended to use those factories.
#
package Foswiki::Contrib::DBCacheContrib::Map;
use base 'Tie::Hash';
# Mixin archivability
use Foswiki::Contrib::DBCacheContrib::Archivable;
push(@ISA, 'Foswiki::Contrib::DBCacheContrib::Archivable');

use strict;
use Assert;

# To operate as a tie, subclasses must implement the methods of
# Tie::Hash, except TIEHASH, and must implement new(). Additional new()
# parameters are passed by name.
# Parameters required to be supported by new() in subclasses are as follows:
#    * =archivist= - reference to an object that implements
#      Foswiki::Contrib::DBCacheContrib::Archivist
#    * =existing= - if defined, reference to an existing object that implements
#      the class being tied to.
#    * =initial= - initial string representing the contents of the map as
#      a space-separated list of equals-separated settings e.g. "a=1 b=2"
# If =existing= is defined, then =archivist= will be ignored.
# For example,
# =my $obj = new Foswiki::Contrib::DBCacheContrib::MemMap(initial=>"a=1 b=2")=
# will create a new MemMap that is not tied to a backing archive and has the
# initial content { a => 1, b => 2 }
# =tie(%map, ref($obj), existing=>$obj)= will tie %map to $obj so you can
# refer to $map{a} and $map{b}.

sub TIEHASH {
    my $class = shift;
    ASSERT(scalar(@_) % 2 == 0) if DEBUG;
    my %args = @_;
    if ($args{existing}) {
        ASSERT(UNIVERSAL::isa($args{existing}, __PACKAGE__)) if DEBUG;
        return $args{existing};
    }
    return $class->new(@_);
}

sub new {
    my $class = shift;
    ASSERT(scalar(@_) % 2 == 0) if DEBUG;
    my %args = @_;
    my $this = bless({}, $class);
    if ($args{existing}) {
        ASSERT(UNIVERSAL::isa($args{existing}, __PACKAGE__)) if DEBUG;
        $this->setArchivist($args{existing}->getArchivist());
    } elsif ($args{archivist}) {
        $this->setArchivist($args{archivist});
    }
    if ($args{initial}) {
        $this->parse($args{initial});
    }
    return $this;
}

# Synonym for FETCH, maintained for compatibility
sub fastget {
    my $this = shift;
    return $this->FETCH(@_);
}

sub equals {
    my ($this, $that) = @_;
    return $this == $that;
}

=begin text

---++ package Foswiki::Contrib::DBCacheContrib::Map
Generic map object for mapping names to things.
Objects in the map are either strings, or other objects that must
support toString.

=cut

sub parse {
    my ($this, $string) = @_;
    my $orig = $string;
    my $n = 1;
    while ( $string !~ m/^[\s,]*$/o ) {
        if ( $string =~ s/^\s*(\w[\w\.]*)\s*=\s*\"(.*?)\"//o ) {
            $this->STORE($1, $2);
        } elsif ( $string =~ s/^\s*(\w[\w\.]*)\s*=\s*([^\s,\}]*)//o ) {
            $this->set($1, $2);
        } elsif ( $string =~ s/^\s*\"(.*?)\"//o ) {
            $this->STORE("\$$n", $1);
            $n++;
        } elsif ( $string =~ s/^\s*(\w[\w+\.]*)\b//o ) {
            $this->STORE($1, 'on');
        } elsif ( $string =~ s/^[^\w\.\"]//o ) {
            # skip bad char or comma
        } else {
            # some other problem
            die 'Foswiki::Contrib::DBCacheContrib::Map::parse: '.
              "Badly formatted attribute string at '$string' in '$orig'";
        }
    }
}

=begin text

---+++ =get($k, $root)= -> datum
   * =$k= - key
   * =$root= what # refers to
Get the value corresponding to key =$k=; return undef if not set.

*Subfield syntax*
   * =get("X",$r)= will get the subfield named =X=.
   * =get("X.Y",$r)= will get the subfield =Y= of the subfield named =X=.
   * =get("[X]",$r) = will get the subfield named =X= (so X[Y] and X.Y are synonymous)..
   * =#= means "reset to root". So =get("#.Y", $r) will return the subfield =Y= of $r (assuming $r is a map!), as will =get("#[Y]"=.

Where the result of a subfield expansion is another object (a Map or an Array) then further subfield expansions can be used. For example,
<verbatim>
get("UserTable[0].Surname", $web);
</verbatim>

See also =Foswiki::Contrib::DBCacheContrib::Array= for syntax that applies to arrays.

=cut

sub get {
    my ( $this, $key, $root ) = @_;

    # If empty string, then we are the required result
    return $this unless $key;

    my $res;
    if ( $key =~ m/^(\w+)(.*)$/o ) {
        # Sub-expression
        #print STDERR "$1\n";
        my $field = $this->FETCH($1);
        if ( $2 && ref( $field )) {
            #print STDERR "\t...$2\n";
            $res = $field->get( $2, $root );
        } else {
            $res = $field;
        }
    } elsif ( $key =~ m/^\.(.*)$/o ) {
        #print STDERR ".$1\n";
        $res = $this->get( $1, $root );
    } elsif ( $key =~ m/^\[(.*)$/o ) {
        my ( $one, $two ) = Foswiki::Contrib::DBCacheContrib::Array::mbrf(
            "[", "]", $1 );
        #print STDERR "[$1]\n";
        my $field = $this->get( $one, $root );
        if ( $two  && ref( $field )) {
            #print STDERR "\t...$two\n";
            $res = $field->get( $two, $root );
        } else {
            $res = $field;
        }
    } elsif ( $key =~ m/^#(.*)$/o ) {
        #print STDERR "#$1\n";
        $res = $root->get( $1, $root );
    } else {
        #print STDERR "ERROR: bad Map expression at $key\n";
    }
    return $res;
}

=begin text

---+++ =set($k, $v)=
   * =$k= - key
   * =$v= - value
Set the given key, value pair in the map.

=cut

sub set {
    my ( $this, $attr, $val ) = @_;
    if ( $attr =~ m/^(\w+)\.(.*)$/o ) {
        $attr = $1;
        my $field = $2;
        if ( !defined( $this->FETCH($attr) )) {
            $this->STORE($attr, $this->{archivist}->newMap());
        }
        $this->FETCH($attr)->set($field, $val);
    } else {
        $this->STORE($attr, $val);
    }
}

=begin text

---+++ =size()= -> integer
Get the size of the map

=cut

sub size {
    my $this = shift;

    return scalar( $this->getKeys() );
}

=begin text

---+++ =remove($index)= -> old value
   * =$index= - integer index
Remove an entry at an index from the array. Return the old value.

=cut

sub remove {
    my ( $this, $attr ) = @_;

    $attr ||= '';

    if ( $attr =~ m/^(\w+)\.(.*)$/o && ref( $this->FETCH($attr) )) {
        $attr = $1;
        my $field = $2;
        return $this->FETCH($attr)->remove( $field );
    } else {
        my $val = $this->FETCH($attr);
        $this->DELETE($attr);
        return $val;
    }
}

=begin text

---+++ =search($search)= -> search result
   * =$search= - Foswiki::Contrib::DBCacheContrib::Search object to use in the search
Search the map for keys that match with the given object.
values. Return a =Foswiki::Contrib::DBCacheContrib::Array= of matching keys.

=cut

sub search {
    my ( $this, $search ) = @_;
    ASSERT($search) if DEBUG;
    require Foswiki::Contrib::DBCacheContrib::MemArray;
    my $result = new Foswiki::Contrib::DBCacheContrib::MemArray();

    foreach my $meta ( $this->getValues() ) {
        if ( $search->matches( $meta )) {
            $result->add( $meta );
        }
    }

    return $result;
}

=begin text

---+++ =toString($limit, $level, $strung)= -> string
   * =$limit= - recursion limit for expansion of elements
   * =$level= - currentl recursion level
Generates an HTML string representation of the object.

=cut

sub toString {
    my ( $this, $limit, $level, $strung ) = @_;

    if ( !defined( $strung )) {
        $strung = {};
    } elsif( $strung->{$this} ) {
        return $this;
    }
    $level = 0 unless (defined($level));
    $limit = 2 unless (defined($limit));
    if ( $level == $limit ) {
        return $this.'.....';
    }
    $strung->{$this} = 1;
    my $key;
    my $ss = '';
    foreach my $key ( $this->getKeys() ) {
        my $item = $key.' = ';
        my $entry = $this->FETCH( $key );
        if ( ref( $entry )) {
            $item .= $entry->toString( $limit, $level + 1, $strung );
        } elsif ( defined( $entry )) {
            $item .= '"'.$entry.'"';
        } else {
            $item .= 'UNDEF';
        }
        $ss .= CGI::li( $item );
    }
    return CGI::ul($ss);
}

1;