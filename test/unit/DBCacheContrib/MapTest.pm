package MapTest;

use strict;
use warnings;

use DBCacheContribTestCase;
our @ISA = qw( DBCacheContribTestCase );

use Foswiki::Contrib::DBCacheContrib::Search;

sub verify_parse1 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a = one bit=\"two\" c" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "one", $attrs->get("a") );
    $this->assert_str_equals( "two", $attrs->get("bit") );
    $this->assert_str_equals( "on",  $attrs->get("c") );
}

sub verify_parse2 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "aname = one,b = \"two\",c" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "one", $attrs->get("aname") );
    $this->assert_str_equals( "two", $attrs->get("b") );
    $this->assert_str_equals( "on",  $attrs->get("c") );
}

sub DIS_verify_parse3 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "x.y=one" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "one", $attrs->get("x.y") );
}

sub verify_parse4 {
    my $this = shift;
    my $attrs;
    eval {
        $this->{ar}->newMap( initial =>
"topic=MacroReqDetails area = \"Signal Integrity\" status=\"Assigned\" release=\"2003.06|All product=\"Fsim\""
        );
    };

    $this->assert_not_null($@);
}

sub verify_tie {
    my $this = shift;
    my %map;
    my $attrs = $this->{ar}->newMap( initial => "a=1 b=2 c=3" );
    tie( %map, ref($attrs), existing => $attrs );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "1", $map{a} );
    $this->assert_str_equals( "2", $map{b} );
    $this->assert_str_equals( "3", $map{c} );
    $map{a} = "one";
    $this->assert_str_equals( "one", $map{a} );
    delete $map{b};
    $map{c} = "three";
    $this->assert( !exists $map{b} );
    $this->assert_str_equals( "three", $map{c} );
}

sub verify_remove {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a = one bit=\"two\" c" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "one", $attrs->remove("a") );
    $this->assert_str_equals( "two", $attrs->remove("bit") );
    $this->assert_str_equals( "on",  $attrs->remove("c") );
    $this->assert_null( $attrs->get("a") );
    $this->assert_null( $attrs->get("bit") );
    $this->assert_null( $attrs->get("c") );
}

sub verify_multipleDefs1 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a = one a=\"two\"" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "two", $attrs->get("a") );
}

sub verify_MultipleDefs2 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a=\"two\" a" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "on", $attrs->remove("a") );
}

sub verify_MultipleDefs3 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a=two a" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "on", $attrs->remove("a") );
}

sub verify_MultipleDefs4 {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a a = one" );
    $this->assert_not_null($attrs);
    $this->assert_str_equals( "one", $attrs->remove("a") );
}

# Where did this come from? Undocumented "feature"
#sub testStringOnOwn {
#  my $this = shift;
#  my $attrs =  $this->{ar}->newMap(initial => "\"able cain\" a=\"no\"" );
#  $this->assert_not_null($attrs);
#  $this->assert_str_equals("able cain", $attrs->get("\$1"));
#  $this->assert_str_equals("no", $attrs->remove("a"));
#}

sub verify_big {
    my $this = shift;
    my $n    = 0;
    my $str  = "";
    while ( $n < 1000 ) {
        $str .= ",a$n=b$n";
        $n++;
    }
    my $attrs = $this->{ar}->newMap( initial => $str );
}

sub verify_set {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "\"able cain\" a=\"no\"" );
    $attrs->set( "2", "two" );
    $this->assert_equals( 3, $attrs->size() );
    $this->assert_str_equals( "able cain", $attrs->remove("\$1") );
    $this->assert_str_equals( "no",        $attrs->remove("a") );
    $this->assert_str_equals( "two",       $attrs->remove("2") );
    $this->assert_equals( 0, $attrs->size() );
}

sub verify_kandv {
    my $this = shift;
    my $attrs = $this->{ar}->newMap( initial => "a=A b=B c=C d=D" );
    $this->assert_equals( 4, $attrs->size() );
    my $tst = "abcd";
    foreach my $val ( $attrs->getKeys() ) {
        $tst =~ s/$val//;
    }
    $this->assert_equals( "", $tst );
    $tst = "ABCD";
    foreach my $val ( $attrs->getValues() ) {
        $tst =~ s/$val//;
    }
    $this->assert_equals( "", $tst );
}

sub verify_search {
    my $this  = shift;
    my $attrs = $this->{ar}->newMap();
    $attrs->set( "a", $this->{ar}->newMap( initial => "f=A" ) );
    $attrs->set( "b", $this->{ar}->newMap( initial => "f=B" ) );
    $attrs->set( "c", $this->{ar}->newMap( initial => "f=C" ) );
    $attrs->set( "d", $this->{ar}->newMap( initial => "f=D" ) );
    $this->assert_equals( 4, $attrs->size() );
    my $search = new Foswiki::Contrib::DBCacheContrib::Search("f=~'(B|C)'");
    my $res    = $attrs->search($search);
    my $tst    = "BC";

    foreach my $e ( $res->getValues() ) {
        my $v = $e->get("f");
        $tst =~ s/$v//;
    }
    $this->assert_str_equals( "", $tst );
}

sub verify_get {
    my $this = shift;
    my $a    = $this->{ar}->newMap( initial => "name=a" );
    my $b    = $this->{ar}->newMap( initial => "name=b" );
    my $c    = $this->{ar}->newMap( initial => "name=c" );

    $a->set( "b",   $b );
    $a->set( "c",   $c );
    $a->set( "ref", "b" );
    $b->set( "a",   $a );
    $b->set( "c",   $c );
    $b->set( "ref", "c" );
    $c->set( "a",   $a );
    $c->set( "b",   $b );
    $c->set( "ref", "a" );

    $this->assert_str_equals( "a", $a->get( "name",         $a ) );
    $this->assert_str_equals( "a", $a->get( ".name",        $a ) );
    $this->assert_str_equals( "a", $a->get( "[name]",       $a ) );
    $this->assert_str_equals( "b", $a->get( "b.name",       $a ) );
    $this->assert_str_equals( "b", $a->get( "b[name]",      $a ) );
    $this->assert_str_equals( "c", $a->get( "[c].name",     $a ) );
    $this->assert_str_equals( "c", $a->get( "[c][name]",    $a ) );
    $this->assert_str_equals( "a", $a->get( "[c.ref].name", $a ) );
}

sub verify_store_retrieve {
    my $this = shift;

    my $root = $this->{ar}->getRoot();
    my $a    = $this->{ar}->newMap( initial => "name=a" );
    my $b    = $this->{ar}->newMap( initial => "name=b" );
    my $c    = $this->{ar}->newMap( initial => "name=c" );

    $a->set( "b",   $b );    # a -> b
    $a->set( "c",   $c );    # a -> c
    $a->set( "ref", "b" );

    #$b->set("a", $a);    # b -> a CYCLE
    $b->set( "c",   $c );    # b -> c
    $b->set( "ref", "c" );

    #$c->set("a", $a);    # c -> a CYCLE
    #$c->set("b", $b);    # c -> b CYCLE
    $c->set( "ref", "a" );

    $root->set( 'a', $a );
    $root->set( 'b', $b );
    $root->set( 'c', $c );

    #use Data::Dumper;
    #print "BEFORE ",Data::Dumper->Dump([$a]), "\n";
    $this->{ar}->sync();
    use Devel::Cycle;
    Devel::Cycle::find_cycle( $this->{ar} );
    undef $this->{ar};

    $this->{ar} = $this->{archivist}->new( $this->{tempfn} );
    $root = $this->{ar}->getRoot();

    #print "AFTER ",Data::Dumper->Dump([$root]),"\n";

    $a = $root->fastget('a');
    $b = $root->fastget('b');
    $c = $root->fastget('c');

    $this->assert_str_equals( "a", $a->get( "name",         $a ) );
    $this->assert_str_equals( "a", $a->get( ".name",        $a ) );
    $this->assert_str_equals( "a", $a->get( "[name]",       $a ) );
    $this->assert_str_equals( "b", $a->get( "b.name",       $a ) );
    $this->assert_str_equals( "b", $a->get( "b[name]",      $a ) );
    $this->assert_str_equals( "c", $a->get( "[c].name",     $a ) );
    $this->assert_str_equals( "c", $a->get( "[c][name]",    $a ) );
    $this->assert_str_equals( "a", $a->get( "[c.ref].name", $a ) );
}

1;
