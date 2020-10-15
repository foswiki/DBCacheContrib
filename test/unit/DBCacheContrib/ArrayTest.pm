package ArrayTest;

use strict;
use warnings;

use DBCacheContribTestCase;
our @ISA = qw( DBCacheContribTestCase );

use Foswiki::Contrib::DBCacheContrib::Search;

use Devel::Leak;

sub verify_array {
    my $this = shift;

    my $array = $this->{ar}->newArray();
    my $i;
    for ( $i = 0 ; $i < 100 ; $i++ ) {
        my $fred = $this->{ar}->newMap( initial => "f1=$i" );
        $array->add($fred);
    }
    for ( $i = 0 ; $i < 100 ; $i++ ) {
        $this->assert_equals( $i, $array->get($i)->get("f1") );
    }
    $i = 0;
    foreach my $v ( $array->getValues() ) {
        $this->assert_equals( $i, $v->get("f1") );
        $this->assert_equals( $i, $array->find($v) );
        $i++;
    }
    my $nonex = $this->{ar}->newMap( initial => "f1=1" );
    $this->assert_equals( -1, $array->find($nonex) );

    $this->assert_equals( 100, $array->size() );
    $this->assert_equals( join( ", ", 0 .. 99 ), $array->get("f1") );
    $this->assert_equals( 99 * 50, $array->sum("f1") );

    my $search = new Foswiki::Contrib::DBCacheContrib::Search("f1=50");
    my $res    = $array->search($search);
    $this->assert_equals( 1,  $res->size() );
    $this->assert_equals( 50, $res->get(0)->get("f1") );

    $search = new Foswiki::Contrib::DBCacheContrib::Search("f1>=90");
    $res    = $array->search($search);
    $this->assert_equals( 10, $res->size() );
    for ( $i = 90 ; $i < 100 ; $i++ ) {
        $this->assert_equals( $i, $res->get( $i - 90 )->get("f1") );
    }
}

sub verify_gets {
    my $this  = shift;
    my $array = $this->{ar}->newArray();
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        my $fred = $this->{ar}->newMap( initial => "f1=$i" );
        $array->add($fred);
    }
    my $k = 0;
    foreach my $i ( $array->getValues() ) {
        $i->set( "f2", $k++ );
    }
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        my $fred = $array->get($i);
        $this->assert_equals( $i, $fred->get("f1") );
        $this->assert_equals( $i, $fred->get("f2") );
    }
}

sub verify_find {
    my $this  = shift;
    my $array = $this->{ar}->newArray();
    for ( my $i = 0 ; $i < 10 ; $i++ ) {
        my $fred = $this->{ar}->newMap( initial => "f1=$i" );
        $this->assert_equals( -1, $array->find($fred) );
        $array->add($fred);
        $this->assert_equals( $i, $array->find($fred) );
    }
}

sub verify_remove {
    my $this  = shift;
    my $array = $this->{ar}->newArray();
    my @nums;
    for ( my $i = 0 ; $i < 3 ; $i++ ) {
        my $fred = $this->{ar}->newMap( initial => "f1=$i" );
        push( @nums, $fred );
        $array->add($fred);
    }

    # from the middle
    my $n = $array->find( $nums[1] );
    $array->remove($n);
    $this->assert_equals( 2, $array->size() );

    # off the front
    $n = $array->find( $nums[0] );
    $array->remove($n);
    $this->assert_equals( 1, $array->size() );

    # off the back
    $n = $array->find( $nums[2] );
    $array->remove($n);
    $this->assert_equals( 0, $array->size() );
}

sub verify_sum {
    my $this = shift;

    my $array = $this->{ar}->newArray();

    $array->add( $this->{ar}->newMap( initial => "f1=1" ) );
    $array->add( $this->{ar}->newMap( initial => "f1=2" ) );
    $array->add( $this->{ar}->newMap() );
    $array->add( $this->{ar}->newArray() );
    $this->assert_equals( 3, $array->sum("f1") );
}

sub verify_getsyntax {
    my $this = shift;

    my $array = $this->{ar}->newArray();

    my $a = $this->{ar}->newMap( initial => "name=a" );
    my $b = $this->{ar}->newMap( initial => "name=b" );
    my $c = $this->{ar}->newMap( initial => "name=c" );

    $a->set( "name", "a" );
    $a->set( "age",  "40" );
    $a->set( "sex",  "M" );

    $b->set( "name", "b" );
    $b->set( "age",  "105" );
    $b->set( "sex",  "M" );

    $c->set( "name", "c" );
    $c->set( "age",  41 );
    $c->set( "sex",  "F" );

    $array->add($a);
    $array->add($b);
    $array->add($c);

    my $s = $array->get("[?age<80]");
    $this->assert( ref($s) );
    $this->assert_equals( 2, $s->size() );
    $this->assert_str_equals( "a", $s->get("0.name") );
    $this->assert_str_equals( "c", $s->get("[1].name") );
    $this->assert_equals( "40, 105, 41", $array->get("age") );
    $this->assert_equals( 186,           $array->sum("age") );

    $s = $array->get("[*name]");
    $this->assert_equals( 3, $s->size() );
    $this->assert_str_equals( "a", $s->get("0") );
    $this->assert_str_equals( "b", $s->get("1") );
    $this->assert_str_equals( "c", $s->get("2") );
}

sub verify_store_retrieve {
    my $this = shift;

    my $root = $this->{ar}->getRoot();

    my $a = $this->{ar}->newMap( initial => "name=a" );
    my $b = $this->{ar}->newMap( initial => "name=b" );
    my $c = $this->{ar}->newMap( initial => "name=c" );

    $a->set( "name", "a" );
    $a->set( "age",  "40" );
    $a->set( "sex",  "M" );

    $b->set( "name", "b" );
    $b->set( "age",  "105" );
    $b->set( "sex",  "M" );

    $c->set( "name", "c" );
    $c->set( "age",  41 );
    $c->set( "sex",  "F" );

    my $array = $this->{ar}->newArray();
    $root->set( 'array', $array );
    $array->add($a);
    $array->add($b);
    $array->add($c);
    my $s = $array->get("[?age<80]");
    $this->assert( ref($s) );

    #use Data::Dumper;
    #print "BEFORE ",Data::Dumper->Dump([$array]), "\n";
    $this->{ar}->sync($array);
    use Devel::Cycle;
    Devel::Cycle::find_cycle($a);

    undef $root;
    undef $array;
    undef $s;
    undef $a;
    undef $b;
    undef $c;
    undef $this->{ar};
    undef $this->{ar};

    $this->{ar} = $this->{archivist}->new( $this->{tempfn} );
    $root = $this->{ar}->getRoot();

    #print "AFTER ",Data::Dumper->Dump([$root]),"\n";
    $array = $root->fastget("array");

    $s = $array->get("[?age<80]");
    $this->assert( ref($s) );
    $this->assert_equals( 2, $s->size() );
    $this->assert_str_equals( "c", $s->get("[1].name") );
    $this->assert_str_equals( "a", $s->get("0.name") );
    $this->assert_equals( 186,           $array->sum("age") );
    $this->assert_equals( "40, 105, 41", $array->get("age") );

    $s = $array->get("[*name]");
    $this->assert_equals( 3, $s->size() );
    $this->assert_str_equals( "a", $s->get("0") );
    $this->assert_str_equals( "b", $s->get("1") );
    $this->assert_str_equals( "c", $s->get("2") );
}

sub verify_tie {
    my $this  = shift;
    my $array = $this->{ar}->newArray();
    my @a;
    tie( @a, ref($array), existing => $array );
    $a[0] = 0;
    $a[2] = 2;
    push( @a, 4 );
    $this->assert_equals( 4, pop(@a) );
    unshift( @a, -1 );
    $this->assert_equals( -1, shift(@a) );
    $a[1] = 1;
    $this->assert_equals( 3, scalar(@a) );
    $this->assert_equals( 0, $a[0] );
    $this->assert_equals( 1, $a[1] );
    $this->assert_equals( 2, $a[2] );
}

1;
