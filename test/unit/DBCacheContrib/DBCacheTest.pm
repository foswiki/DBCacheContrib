package DBCacheTest;

use strict;
use warnings;

use DBCacheContribTestCase;
our @ISA = qw( DBCacheContribTestCase );

use Foswiki::Contrib::DBCacheContrib;
use Foswiki::Contrib::DBCacheContrib::MemMap;
use Foswiki::Contrib::DBCacheContrib::MemArray;

use Foswiki::Func;
use Foswiki::Meta;

use Devel::Leak;
use Data::Dumper ();

my $baseText = <<TEXT;
CategoryForm
   * Set HAIR = beehive
   * Local BEARD = goatee
TEXT

sub set_up {
    my $this = shift;

    $this->SUPER::set_up();

    my $meta =
      Foswiki::Meta->new( $this->{session}, $this->{test_web}, "FormTest" );

    $meta->putKeyed(
        'FIELD',
        {
            name  => "FieldOne",
            title => "FieldOne",
            value => "Value One",
        }
    );
    $meta->putKeyed(
        'FIELD',
        {
            name  => "FieldTwo",
            title => "FieldTwo",
            value => "Value Two",
        }
    );
    $meta->putKeyed(
        'FIELD',
        {
            name  => "FieldThree",
            title => "FieldThree",
            value => "7.1",
        }
    );
    $meta->putKeyed(
        'FIELD',
        {
            name  => "BackSlash",
            title => "Back Slash",
            value => "One",
        }
    );
    $meta->putKeyed(
        'FILEATTACHMENT',
        {
            name    => "conftest.val",
            attr    => "",
            comment => "Bangra bingo",
            date    => "1091696180",
            path    => "conftest.val",
            size    => "8",
            user    => "guest",
            version => "1.2",
        }
    );
    $meta->putKeyed(
        'FILEATTACHMENT',
        {
            name    => "left.gif",
            attr    => "",
            comment => "left arrer",
            date    => "1091696102",
            path    => "left.gif",
            size    => "107",
            user    => "guest",
            version => "1.1",
        }
    );
    $meta->putKeyed(
        'FILEATTACHMENT',
        {
            name    => "right.gif",
            attr    => "h",
            comment => "",
            date    => "1091696127",
            path    => "right.gif",
            size    => "105",
            user    => "guest",
            version => "1.1",
        }
    );

    $meta->put(
        'TOPICINFO',
        {
            author  => "guest",
            date    => "1089644791",
            format  => "1.0",
            version => "1.1",
        }
    );
    $meta->put( 'FORM', { name => "ThisForm", } );
    $meta->put(
        'TOPICMOVED',
        {
            by   => "guest",
            date => "1091696242",
            from => "$this->{test_web}.FormsTest",
            to   => "$this->{test_web}.FormTest",
        }
    );
    $meta->put( 'TOPICPARENT', { name => "WebHome", } );

    $meta->putKeyed(
        'PREFERENCE',
        {
            type  => 'Set',
            name  => "SHIRT",
            value => "purple",
        }
    );
    $meta->putKeyed(
        'PREFERENCE',
        {
            type  => 'Local',
            name  => "TROUSERS",
            value => "yellow",
        }
    );

    Foswiki::Func::saveTopic( $this->{test_web}, "FormTest", $meta, $baseText );
    $this->{test_meta} = $meta;
}

sub verify_loadSimple {
    my $this = shift;

    my $db =
      new Foswiki::Contrib::DBCacheContrib( $this->{test_web}, undef, 0, 1 );
    my @res = $db->load();
    $this->assert_str_equals( "0 3 0", join( ' ', @res ) );
    my $topic = $db->cache->get("WebPreferences");
    $this->assert($topic);
    my $info = $topic->get("info");
    $this->assert_not_null($info);
    my $user = $info->get("author");
    $user = $this->{session}->{users}->getWikiName($user);
    $this->assert_str_equals( "WikiGuest", $user );
    $this->assert_str_equals( "1.1",       $info->get("format") );

    $topic = $db->cache->get("FormTest");

    $this->assert_not_null($topic);
    $info = $topic->get("info");
    $this->assert_not_null($info);
    $user = $info->get("author");
    $user = $this->{session}->{users}->getWikiName($user);
    $this->assert_str_equals( "WikiGuest", $user );
    $this->assert_str_equals( "1.1",       $info->get("format") );
    $this->assert_str_equals( "1",         $info->get("version") );
    $this->assert_str_equals( "WebHome",   $topic->get("parent") );
    $this->assert_str_equals( $baseText,   $topic->get("text") );
    $this->assert_str_equals( "ThisForm",  $topic->get("form") );
    my $form = $topic->get("ThisForm");
    $this->assert_not_null($form);
    $this->assert_str_equals( "Value One", $form->get("FieldOne") );
    $this->assert_str_equals( "Value Two", $form->get("FieldTwo") );
    $this->assert_equals( 7.1, $form->get("FieldThree") );
    $this->assert_str_equals( "One", $form->get("BackSlash") );

    my $atts = $topic->get("attachments");
    $this->assert_not_null($atts);
    for my $i ( 0 .. 2 ) {
        my $att = $atts->get("[$i]");
        $this->assert_not_null($att);
        if ( "conftest.val" eq $att->get("name") ) {
            $this->assert_str_equals( "",             $att->get("attr") );
            $this->assert_str_equals( "Bangra bingo", $att->get("comment") );
            $this->assert_equals( "1091696180", $att->get("date") );
            $this->assert_str_equals( "conftest.val", $att->get("path") );
            $this->assert_str_equals( 8,              $att->get("size") );
            $this->assert_str_equals( "guest",        $att->get("user") );
            $this->assert_equals( 1.2, $att->get("version") );
        }
        elsif ( "left.gif" eq $att->get("name") ) {
            $this->assert_str_equals( "",           $att->get("attr") );
            $this->assert_str_equals( "left arrer", $att->get("comment") );
            $this->assert_equals( 1091696102, $att->get("date") );
            $this->assert_str_equals( "left.gif", $att->get("path") );
            $this->assert_str_equals( 107,        $att->get("size") );
            $this->assert_str_equals( "guest",    $att->get("user") );
            $this->assert_equals( 1.1, $att->get("version") );
        }
        else {
            $this->assert_str_equals( "right.gif", $att->get("name") );
            $this->assert_str_equals( "h",         $att->get("attr") );
            $this->assert_str_equals( "",          $att->get("comment") );
            $this->assert_equals( 1091696127, $att->get("date") );
            $this->assert_str_equals( "right.gif", $att->get("path") );
            $this->assert_str_equals( 105,         $att->get("size") );
            $this->assert_str_equals( "guest",     $att->get("user") );
            $this->assert_equals( 1.1, $att->get("version") );
        }
    }

    my $moved = $topic->get("moved");
    $this->assert_not_null($moved);
    $this->assert_str_equals( "guest", $moved->get("by") );
    $this->assert_equals( 1091696242, $moved->get("date") );
    $this->assert_str_equals( "$this->{test_web}.FormsTest",
        $moved->get("from") );
    $this->assert_str_equals( "$this->{test_web}.FormTest", $moved->get("to") );

    $db    = undef;
    $atts  = undef;
    $moved = undef;
    @res   = ();
}

sub verify_cache {
    my $this = shift;

    my $db = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    $this->assert_null( $db->cache );

    $this->assert_str_equals( $this->{test_web}, $db->{_web} );

    # There should be no cache there
    my @res = $db->load();
    $this->assert_equals( "0 3 0", join( ' ', @res ) );
    $this->assert_not_null( $db->cache );

    # Should be up to date now
    @res = $db->load();
    $this->assert_str_equals( "0 0 0", join( ' ', @res ) );

    # There's a cache there now; read all from cache
    $db = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );

    #print STDERR "RELOADED ".Data::Dumper->Dump([$db]);
    $this->assert_null( $db->cache );
    @res = $db->load();
    $this->assert_str_equals( "3 0 0", join( ' ', @res ) );
    $this->assert_not_null( $db->cache );

    #    $this->checkSameAs($initial,$db);

    @res = $db->load();
    $this->assert_str_equals( "0 0 0", join( ' ', @res ) );

    #    $this->checkSameAs($initial,$db);

    sleep(1);    # wait for clock tick, and re-save one file
    Foswiki::Func::saveTopic( $this->{test_web}, "FormTest", $this->{test_meta},
        $baseText );

    # One file in the cache has been touched
    $db  = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    @res = $db->load(1);
    $this->assert_str_equals( "2 1 0", join( ' ', @res ) );

    #    $this->checkSameAs($initial,$db);

    $db  = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    @res = $db->load();
    $this->assert_str_equals( "3 0 0", join( ' ', @res ) );

    #    $this->checkSameAs($initial,$db);

    # A new file has been created
    Foswiki::Func::saveTopicText( $this->{test_web}, "NewFile", "Blah" );

    $db  = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    @res = $db->load(1);
    $this->assert_str_equals( "3 1 0", join( ' ', @res ) );

    # One file in the cache has been deleted
    Foswiki::Func::moveTopic( $this->{test_web}, "FormTest", "Trash",
        "FormTest$$" );
    $db  = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    @res = $db->load(1);
    $this->assert_str_equals( "3 0 1", join( ' ', @res ) );

    Foswiki::Func::moveTopic( $this->{test_web}, "NewFile", "Trash",
        "NewFile$$" );
    Foswiki::Func::saveTopic( $this->{test_web}, "FormTest", $this->{test_meta},
        $baseText );
    $db  = new Foswiki::Contrib::DBCacheContrib( $this->{test_web} );
    @res = $db->load(1);
    $this->assert_str_equals( "2 1 1", join( ' ', @res ) );

    #    $this->checkSameAs($initial, $db);
    $this->assert( $db->cache->isa('Foswiki::Contrib::DBCacheContrib::Map') );
}

sub checkSameAs {
    my ( $this, $first, $second, $cmping, $checked, $where ) = @_;
    $cmping  = "ROOT" unless ( defined($cmping) );
    $checked = {}     unless ( defined($checked) );
    return if ( $checked->{$first} );
    $checked->{$first} = 1;
    $where ||= join( ' ', caller() );
    my $type = ref($first);

    $this->assert_str_equals( $type, ref($second),
        "$cmping:\n|$type|\n|" . ref($second) . "|\nat $where" );
    if ( $type =~ /Map$/ || $type =~ /DBCacheContrib$/ ) {
        $this->checkSameAsMap( $first, $second, $cmping, $checked, $where );
    }
    elsif ( $type =~ /Array$/ ) {
        $this->checkSameAsArray( $first, $second, $cmping, $checked, $where );
    }
    elsif ( $type =~ /FileTime$/ ) {
        $this->checkSameAsFileTime( $first, $second, $cmping, $checked,
            $where );
    }
    else {
        $this->assert( 0, ref($first) . " != " . ref($second) . " $where" );
    }
}

sub checkSameAsMap {
    my ( $this, $first, $second, $cmping, $checked, $where ) = @_;

    foreach my $k ( $first->getKeys() ) {
        my $a = $first->FETCH($k)  || "";
        my $b = $second->FETCH($k) || "";
        my $c = "$cmping.$k";
        if ( ref($a) ) {
            $this->checkSameAs( $a, $b, $c, $checked, $where );
        }
        elsif ( $k !~ /^_/ && $c !~ /\.date$/ ) {
            if ( $c =~ /\.text$/ ) {
                $this->assert_matches( qr/^$a\s*$/, $b, "$c ($a!=$b) $where" );
            }
            elsif ( $c =~ /\.all$/ ) {

                # Skip, incomparable text + meta
            }
            else {
                $this->assert_str_equals( $a, $b, "$c ($a!=$b) $where" );
            }
        }
    }
}

sub checkSameAsArray {
    my ( $this, $first, $second, $cmping, $checked, $where ) = @_;

    $this->assert_equals( $first->size(), $second->size(),
        $cmping . " " . $first->size() . " " . $second->size() . $where );
    my $i = 0;
    foreach my $a ( @{ $first->{values} } ) {
        my $c = "$cmping\[$i\]";
        my $b = $second->get( $i++ );
        if ( ref($a) ) {
            $this->checkSameAs( $a, $b, $c, $checked, $where );
        }
        else {
            if ( $c =~ /\.text$/ ) {
                $this->assert_matches( qr/^$a\s*$/, $b, "$c ($a!=$b) $where" );
            }
            else {
                $this->assert_str_equals( $a, $b, "$c ($a!=$b) $where" );
            }
        }
    }
}

sub checkSameAsFileTime {
    my ( $this, $first, $second, $cmping, $checked, $where ) = @_;
    $this->assert_str_equals( $first->{file}, $second->{file},
        $cmping . $where );
}

1;
