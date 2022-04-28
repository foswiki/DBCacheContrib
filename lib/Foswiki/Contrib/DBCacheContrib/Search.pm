# See bottom of file for license and copyright information

=begin TML

---+ package Foswiki::Contrib::DBCacheContrib::Search

Search operators work on the fields of a Foswiki::Contrib::DBCacheContrib::Map.

---++ Example
Get a list of attachments that have a date earlier than 1st January 2000
<verbatim>
  $db = new Foswiki::Contrib::DBCacheContrib::DBCache( $web ); # always done
  $db->load();
  my $search = new Foswiki::Contrib::DBCacheContrib::Search("date EARLIER_THAN '1st January 2000'");

  foreach my $topic ($db->getKeys()) {
     my $attachments = $topic->fastget("attachments");
     foreach my $val ($attachments->getValues()) {
       if ($search->matches($val)) {
          print $val->fastget("name") . "\n";
       }
     }
  }
</verbatim>

A search object implements the "matches" method as its general
contract with the rest of the world.

=cut

package Foswiki::Contrib::DBCacheContrib::Search;

use strict;
use warnings;
use Assert;
use Foswiki::Contrib::DBCacheContrib ();
use Foswiki::Time                    ();

# Operator precedences
my %operators = (
    'lc'                 => { exec => \&OP_lc,                 prec => 5 },
    'uc'                 => { exec => \&OP_uc,                 prec => 5 },
    '='                  => { exec => \&OP_equal,              prec => 4 },
    '=~'                 => { exec => \&OP_match,              prec => 4 },
    '~'                  => { exec => \&OP_contains,           prec => 4 },
    '!='                 => { exec => \&OP_not_equal,          prec => 4 },
    '>='                 => { exec => \&OP_gtequal,            prec => 4 },
    '<='                 => { exec => \&OP_smequal,            prec => 4 },
    '>'                  => { exec => \&OP_greater,            prec => 4 },
    '<'                  => { exec => \&OP_smaller,            prec => 4 },
    'EARLIER_THAN'       => { exec => \&OP_earlier_than,       prec => 4 },
    'EARLIER_THAN_OR_ON' => { exec => \&OP_earlier_than_or_on, prec => 4 },
    'LATER_THAN'         => { exec => \&OP_later_than,         prec => 4 },
    'LATER_THAN_OR_ON'   => { exec => \&OP_later_than_or_on,   prec => 4 },
    'WITHIN_DAYS'        => { exec => \&OP_within_days,        prec => 4 },
    'IS_DATE'            => { exec => \&OP_is_date,            prec => 4 },
    '!'                  => { exec => \&OP_not,                prec => 3 },
    'AND'                => { exec => \&OP_and,                prec => 2 },
    'OR'                 => { exec => \&OP_or,                 prec => 1 },
    'FALSE'              => { exec => \&OP_false,              prec => 0 },
    'NODE'               => { exec => \&OP_node,               prec => 0 },
    'NUMBER'             => { exec => \&OP_number,             prec => 0 },
    'REF'                => { exec => \&OP_ref,                prec => 0 },
    'STRING'             => { exec => \&OP_string,             prec => 0 },
    'TRUE'               => { exec => \&OP_true,               prec => 0 },
    'n2d'                => { exec => \&OP_n2d,                prec => 5 },
    'd2n'                => { exec => \&OP_d2n,                prec => 5 },
    'length'             => { exec => \&OP_length,             prec => 5 },
    'defined'            => { exec => \&OP_defined,            prec => 5 },
    'ALLOWS'             => { exec => \&OP_allows,             prec => 5 },
    'displayValue'       => { exec => \&OP_displayValue,       prec => 5 },
    'translate'          => { exec => \&OP_translate,          prec => 5 },
);

my $bopRE =
"AND\\b|OR\\b|!=|=~?|~|<=?|>=?|LATER_THAN\\b|EARLIER_THAN\\b|LATER_THAN_OR_ON\\b|EARLIER_THAN_OR_ON\\b|WITHIN_DAYS\\b|IS_DATE\\b|ALLOWS\\b";
my $uopRE = "!|[lu]c\\b|d2n|n2d|length|defined|displayValue|translate";

my $now = time();

my $globalContext;    # set as part of a call to match()

# PUBLIC STATIC used for testing only; force 'now' to be a particular
# time.
sub forceTime {
    my $t = shift;

    $now = Foswiki::Contrib::DBCacheContrib::parseDate($t);
}

=begin TML

---+++ =new($string)=
   * =$string= - string containing an expression to parse
Construct a new search node by parsing the passed expression.

=cut

sub new {
    my ( $class, $string, $left, $op, $right ) = @_;

    my $this;
    if ( defined($string) ) {
        if ( $string =~ m/^\s*$/o ) {
            $this = new Foswiki::Contrib::DBCacheContrib::Search( undef, undef,
                "TRUE", undef );
        }
        else {
            my $rest;
            ( $this, $rest ) = _parse($string);
            print STDERR "WARNING: '$rest'\n"
              if defined $rest && $rest !~ /^\s*$/;
        }
    }
    else {
        $this          = {};
        $this->{right} = $right;
        $this->{left}  = $left;
        $this->{op}    = $op;
        $this          = bless( $this, $class );
    }

    $now = time();    # update $now

    return $this;
}

sub DESTROY {
    my $this = shift;
    undef $this->{right};
    undef $this->{left};
    undef $this->{op};
}

# PRIVATE STATIC generate a Search by popping the top two operands
# and the top operator. Push the result back onto the operand stack.
sub _apply {
    my ( $opers, $opands ) = @_;
    my $o = pop(@$opers);
    my $r = pop(@$opands);
    ASSERT( defined $r ) if DEBUG;
    die "Bad search" unless defined($r);
    my $l = undef;
    if ( $o =~ /^$bopRE$/o ) {
        $l = pop(@$opands);
        die "Bad search" unless defined($l);
    }
    my $n = new Foswiki::Contrib::DBCacheContrib::Search( undef, $l, $o, $r );
    push( @$opands, $n );
}

# PRIVATE STATIC simple stack parser for grabbing boolean expressions
sub _parse {
    my $string = shift;

    $string .= " ";
    my @opands;
    my @opers;
    while ( $string !~ m/^\s*$/o ) {
        if ( $string =~ s/^\s*($bopRE)//o ) {

            # Binary comparison op
            my $op = $1;
            while ( scalar(@opers) > 0
                && $operators{$op}->{prec} <
                $operators{ $opers[$#opers] }->{prec} )
            {
                _apply( \@opers, \@opands );
            }
            push( @opers, $op );
        }
        elsif ( $string =~ s/^\s*($uopRE)//o ) {

            # unary op
            push( @opers, $1 );
        }
        elsif ( $string =~ s/^\s*\'(.*?)(?<!\\)\'//o ) {
            push(
                @opands,
                new Foswiki::Contrib::DBCacheContrib::Search(
                    undef, undef, "STRING", $1
                )
            );
        }
        elsif ( $string =~ s/^\s*([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)\b//io ) {
            push(
                @opands,
                new Foswiki::Contrib::DBCacheContrib::Search(
                    undef, undef, "NUMBER", $1
                )
            );
        }
        elsif ( $string =~ s/^\s*(\@\w+(?:\.\w+)+)//o ) {
            push(
                @opands,
                new Foswiki::Contrib::DBCacheContrib::Search(
                    undef, undef, "REF", $1
                )
            );
        }
        elsif ( $string =~ s/^\s*([\w\.]+)//o ) {
            push(
                @opands,
                new Foswiki::Contrib::DBCacheContrib::Search(
                    undef, undef, "NODE", $1
                )
            );
        }
        elsif ( $string =~ s/^\s*\(//o ) {
            my $oa;
            ( $oa, $string ) = _parse($string);
            push( @opands, $oa );
        }
        elsif ( $string =~ s/^\s*\)//o ) {
            last;
        }
        else {
            return ( undef, "Parser stuck at $string" );
        }
    }
    while ( scalar(@opers) > 0 ) {
        _apply( \@opers, \@opands );
    }
    ASSERT( scalar(@opands) == 1 ) if DEBUG;
    die "Bad search" unless ( scalar(@opands) == 1 );
    return ( pop(@opands), $string );
}

sub matches {
    my ( $this, $map, $context ) = @_;

    my $oldContext = $globalContext;
    $globalContext = $context if defined $context;

    my $handler = $operators{ $this->{op} };
    my $result  = 0;
    $result = $handler->{exec}( $this->{right}, $this->{left}, $map )
      if defined $handler;

    $globalContext = $oldContext if defined $context;

    return $result;
}

sub OP_true { return 1; }

sub OP_false { return 0; }

sub OP_string { return $_[0]; }

sub OP_number { return $_[0]; }

sub OP_or {
    my ( $r, $l, $map ) = @_;

    return unless defined $l;

    my $lval = $l->matches($map);
    return 1 if $lval;

    return unless defined $r;

    my $rval = $r->matches($map);
    return 1 if $rval;

    return 0;
}

sub OP_and {
    my ( $r, $l, $map ) = @_;

    return unless defined $l;

    my $lval = $l->matches($map);
    return 0 unless $lval;

    return unless defined $r;

    my $rval = $r->matches($map);
    return 1 if $rval;

    return 0;
}

sub OP_not {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    return ( $r->matches($map) ) ? 0 : 1;
}

sub OP_lc {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $rval = $r->matches($map);
    return unless defined $rval;

    return lc($rval);
}

sub OP_uc {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $rval = $r->matches($map);
    return unless defined $rval;

    return uc($rval);
}

sub OP_n2d {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $rval = $r->matches($map);
    return unless defined $rval;

    return Foswiki::Time::formatTime($rval);
}

sub OP_d2n {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $rval = $r->matches($map);
    return unless defined $rval;

    return Foswiki::Contrib::DBCacheContrib::parseDate($rval);
}

sub OP_length {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $rval = $r->matches($map);
    return unless defined $rval;

    if ( ref($rval) eq 'ARRAY' ) {
        return scalar(@$rval);
    }
    elsif ( ref($rval) eq 'HASH' ) {
        return scalar( keys %$rval );
    }
    elsif ( ref($rval) && UNIVERSAL::can( $rval, "size" ) ) {
        return $rval->size();
    }
    else {
        return length($rval);
    }
}

sub OP_defined {
    my ( $r, $l, $map ) = @_;

    return 0 unless defined $r;

    my $rval = $r->matches($map);
    return 0 unless defined $rval;

    return 1;
}

sub OP_allows {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    my $rval = $r->matches($map);

    my $webDB;
    $webDB = $globalContext->{webDB} if defined $globalContext;

    my ( $web, $topic ) =
      Foswiki::Func::normalizeWebTopicName( $webDB ? $webDB->{_web} : '',
        $lval );

    return 0 unless Foswiki::Func::topicExists( $web, $topic );

    my $user = Foswiki::Func::getWikiName();
    return Foswiki::Func::checkAccessPermission( $rval, $user, undef, $topic,
        $web );
}

sub OP_node {
    my ( $r, $l, $map ) = @_;

    return unless ( $map && defined $r );

    my $val = $map->getFieldValue($r);
    $val = $map->get($r) unless defined $val;
    return $val;
}

sub OP_displayValue {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $fieldName = $r->matches($map);
    return unless defined $fieldName;

    my $fieldDef = $map->getFieldDef($fieldName);
    return unless $fieldDef;

    my $fieldValue = $map->getDisplayValue($fieldName);
    return unless $fieldValue;

    $fieldValue = $map->translate($fieldValue)
      if $fieldDef->{type} =~ /\+values/;

    return $fieldValue;
}

sub OP_translate {
    my ( $r, $l, $map ) = @_;

    return unless defined $r;

    my $str = $r->matches($map);
    return unless defined $str;
    return $map->translate($str);
}

sub OP_ref {
    my ( $r, $l, $map ) = @_;

    return unless ( $map && defined $r );

    # get web db
    my $webDB;
    $webDB = $globalContext->{webDB} if defined $globalContext;

    # parse reference chain
    my %seen;
    my $val;
    if ( $r =~ /^\@(\w+)\.(.*)$/ ) {
        my $ref = $1;
        $r = $2;

        # protect against infinite loops
        return if $seen{$ref};    # outch
        $seen{$ref} = 1;

        # get form
        my $form = $map->FETCH('form');
        return unless $form;      # no form

        # get refered topic
        $form = $map->FETCH($form);
        $ref  = $form->FETCH($ref);
        return unless $ref;       # unknown field

        $ref =~ s/^\s+|\s+$//g;
        my @vals = ();
        foreach my $refItem ( split( /\s*,\s*/, $ref ) ) {
            my ( $refWeb, $refTopic ) =
              Foswiki::Func::normalizeWebTopicName(
                $webDB ? $webDB->{_web} : '', $refItem );

            if ( !$webDB || $refWeb ne $webDB->{_web} ) {
                $webDB = Foswiki::Plugins::DBCachePlugin::getDB($refWeb);
            }

            # get topic object
            unless ( defined $webDB ) {
                print STDERR
                  "WARNING: web $refWeb not found processing REF operator\n";
                next;
            }

            $map = $webDB->fastget($refTopic);
            next unless $map;

            # the tail is a property of the referenced topic
            my $form = $map->fastget("form");
            next unless $form;
            $form = $map->fastget($form);
            next unless $form;

            $val = $form->get($r);
            $val = $map->get($r) unless defined $val;

            push @vals, $val if defined $val && $val ne '';
        }
        $val = join( ", ", @vals );
    }
    else {

        # the tail is a property of the referenced topic
        my $form = $map->fastget("form");
        $form = $map->fastget($form) if defined $form;
        $val  = $form->get($r)       if defined $form;
        $val = $map->get($r) unless defined $val;
    }

    return $val;
}

sub OP_equal {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    my $rval = $r->matches($map);

    return 1 if !defined($lval) && !defined($rval);
    return 0 if !defined $lval || !defined($rval);

    return ( $lval =~ m/^$rval$/ ) ? 1 : 0;
}

sub OP_not_equal {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    my $rval = $r->matches($map);

    return 0 if !defined($lval) && !defined($rval);
    return 1 if !defined $lval || !defined($rval);

    return ( $lval =~ m/^$rval$/ ) ? 0 : 1;
}

sub OP_match {
    my ( $r, $l, $map ) = @_;

    return unless defined $l;

    my $lval = $l->matches($map);
    return 0 unless defined $lval;

    return unless defined $r;

    my $rval = $r->matches($map);
    return 0 unless defined $rval;

    return ( $lval =~ m/$rval/ ) ? 1 : 0;
}

sub OP_contains {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return 0 unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval =~ s/\./\\./g;
    $rval =~ s/\?/./g;
    $rval =~ s/\*/.*/g;

    return ( $lval =~ m/$rval/ ) ? 1 : 0;
}

sub OP_greater {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    ($lval) = $lval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    ($rval) = $rval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $rval;

    return ( $lval > $rval ) ? 1 : 0;
}

sub OP_smaller {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    ($lval) = $lval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    ($rval) = $rval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $rval;

    return ( $lval < $rval ) ? 1 : 0;
}

sub OP_gtequal {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    ($lval) = $lval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    ($rval) = $rval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $rval;

    return ( $lval >= $rval ) ? 1 : 0;
}

sub OP_smequal {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    ($lval) = $lval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    ($rval) = $rval =~ /([+-]?\d+(?:\.\d*)?(?:e[+-]?\d+)?)/;
    return unless defined $rval;

    return ( $lval <= $rval ) ? 1 : 0;
}

sub OP_within_days {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    return ( $lval >= $now && workingDays( $now, $lval ) <= $rval ) ? 1 : 0;
}

sub OP_later_than {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval = Foswiki::Contrib::DBCacheContrib::parseDate($rval);
    return unless defined $rval;

    return ( $lval > $rval ) ? 1 : 0;
}

sub OP_later_than_or_on {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval = Foswiki::Contrib::DBCacheContrib::parseDate($rval);
    return unless defined $rval;

    return ( $lval >= $rval ) ? 1 : 0;
}

sub OP_earlier_than {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval = Foswiki::Contrib::DBCacheContrib::parseDate($rval);
    return unless defined $rval;

    return ( $lval < $rval ) ? 1 : 0;
}

sub OP_earlier_than_or_on {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && defined $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return unless defined $lval;

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval = Foswiki::Contrib::DBCacheContrib::parseDate($rval);
    return unless defined $rval;

    return ( $lval <= $rval ) ? 1 : 0;
}

sub OP_is_date {
    my ( $r, $l, $map ) = @_;

    return unless defined $l && $r;

    my $lval = $l->matches($map);
    return unless defined $lval;

    $lval = Foswiki::Contrib::DBCacheContrib::parseDate($lval);
    return 0 unless ( defined($lval) );

    my $rval = $r->matches($map);
    return unless defined $rval;

    $rval = Foswiki::Contrib::DBCacheContrib::parseDate($rval);
    return unless defined $rval;

    return ( $lval == $rval ) ? 1 : 0;
}

# PUBLIC STATIC calculate working days between two times
# Published because it's useful elsewhere
sub workingDays {
    my ( $start, $end ) = @_;

    use integer;
    my $elapsed_days = ( $end - $start ) / ( 60 * 60 * 24 );

    # total number of elapsed 7-day weeks
    my $whole_weeks = $elapsed_days / 7;
    my $extra_days = $elapsed_days - ( $whole_weeks * 7 );
    if ( $extra_days > 0 ) {
        my @lt   = localtime($start);
        my $wday = $lt[6];              # weekday, 0 is sunday

        if ( $wday == 0 ) {
            $extra_days-- if ( $extra_days > 0 );
        }
        else {
            $extra_days-- if ( $extra_days > ( 6 - $wday ) );
            $extra_days-- if ( $extra_days > ( 6 - $wday ) );
        }
    }
    return $whole_weeks * 5 + $extra_days;
}

=begin TML

---+++ =toString()= -> string
Generates a string representation of the object.

=cut

sub toString {
    my $this = shift;

    my $text = "";
    if ( defined( $this->{left} ) ) {
        if ( !ref( $this->{left} ) ) {
            $text .= $this->{left};
        }
        else {
            $text .= "(" . $this->{left}->toString() . ")";
        }
        $text .= " ";
    }
    $text .= $this->{op};
    if ( defined $this->{right} ) {
        $text .= " ";
        if ( !ref( $this->{right} ) ) {
            $text .= "'" . $this->{right} . "'";
        }
        else {
            $text .= "(" . $this->{right}->toString() . ")";
        }
    }
    return $text;
}

=begin TML

--+++ =addOperator(%oper)
Add an operator to the parser

=%oper= is a hash, containing the following fields:
   * =name= - operator string
   * =prec= - operator precedence, positive non-zero integer.
     Larger number => higher precedence.
   * =arity= - set to 1 if this operator is unary, 2 for binary. Arity 0
     is legal, should you ever need it.
   * =exec= - the handler to implement the new operator

=cut

sub addOperator {
    my %oper = @_;

    my $name = $oper{name};
    die "illegal operator definition" unless $name;

    $operators{$name} = \%oper;

    if ( $oper{arity} == 2 ) {
        $bopRE .= "|\\b$name\\b";
    }
    elsif ( $oper{arity} == 1 ) {
        $uopRE .= "|\\b$name\\b";
    }
    else {
        die "illegal operator definition";
    }
}

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
