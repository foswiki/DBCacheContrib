# See bottom of file for license and copyright information

package Foswiki::Contrib::DBCacheContrib;

use strict;
use Assert;

use Foswiki::Attrs   ();
use Foswiki::Sandbox ();

=begin TML

---++ package DBCacheContrib

General purpose cache that presents Foswiki topics as expanded hashes
Useful for rapid read and search of the database. Only works on one web.

Typical usage:
<verbatim>
  use Foswiki::Contrib::DBCacheContrib;

  $db = new Foswiki::Contrib::DBCacheContrib( $web ); # always done
  $db->load(); # may be always done, or only on demand when a tag is parsed that needs it

  # the DB is a hash of topics keyed on their name
  foreach my $topic ($db->getKeys()) {
     my $attachments = $db->fastget($topic)->fastget("attachments");
     # attachments is an array
     foreach my $val ($attachments->getValues()) {
       my $aname = $attachments->fastget("name");
       my $acomment = $attachments->fastget("comment");
       my $adate = $attachments->fastget("date");
       ...
     }
  }
</verbatim>
As topics are loaded, the readTopicLine method gives subclasses an opportunity
to apply special processing to indivual lines, for example to extract special
syntax such as %ACTION lines, or embedded tables in the text. See
FormQueryPlugin for an example of this.

=cut

our $VERSION = '4.30';
our $RELEASE = '28 May 2018';
our $SHORTDESCRIPTION =
  'Reusable code that treats forms as if they were table rows in a database';

our $INLINE_IMAGE =
qr/<img\s+[^>]*?\s*src=["']data:(?:[a-z]+\/[a-z\-\.\+]+)?(?:;[a-z\-]+\=[a-z\-]+)?;base64,.*?["']\s*[^>]*?\s*\/?>/;

=begin TML

---+++ =new($web, $cacheName[, $standardSchema ])=
Construct a new DBCache object.
   * =$web= name of web to create the object for.
   * =$cacheName= name of cache file
   * =$standardSchema= Set to 1 this will load the cache using the
     'standard' Foswiki schema, rather than the original DBCacheContrib
     extended schema.

=cut

sub new {
    my ( $class, $web, $cacheName, $standardSchema ) = @_;
    $cacheName ||= '_DBCache' . ( $standardSchema ? '_standard' : '' );

    # Backward compatibility
    unless ( $Foswiki::cfg{DBCacheContrib}{Archivist} ) {
        $Foswiki::cfg{DBCacheContrib}{Archivist} =
          'Foswiki::Contrib::DBCacheContrib::Archivist::Storable';
    }
    eval "use $Foswiki::cfg{DBCacheContrib}{Archivist}";
    die $@ if ($@);

    my $workDir = Foswiki::Func::getWorkArea('DBCacheContrib');
    $web =
      Foswiki::Sandbox::untaint( $web, \&Foswiki::Sandbox::validateWebName );
    my $this = bless(
        {
            _cache     => undef,        # pointer to the DB, load on demand
            _web       => $web,
            _cachename => $cacheName,
            _standardSchema => $standardSchema,
        },
        $class
    );

    # Create the archivist. This will connect to an existing DB or create
    # a new DB if required.

    $this->{archivist} =
      $Foswiki::cfg{DBCacheContrib}{Archivist}->new( $web . '.' . $cacheName );

    return $this;
}

sub getArchivist {
    my $this = shift;
    return $this->{archivist};
}

sub cache {
    my $this = shift;
    return $this->{_cache};
}

######################################################################
# In order for this class to operate as documented it has to implement
# Foswiki::Map. However it no longer directly subclasses Map since the
# move to BerkeleyDB. So we have to facade the cache instead. Note that
# this will *not* make this class tieable, as it doesn't inherit the
# necessary methods. The following methods are therefore deprecated; they
# are simply facades on the corresponding Map methods.

sub getKeys {
    my $this = shift;
    return $this->{_cache}->getKeys();
}

sub getValues {
    my $this = shift;
    return $this->{_cache}->getValues();
}

sub fastget {
    my $this = shift;
    return $this->{_cache}->fastget(@_);
}

sub equals {
    my $this = shift;
    return $this->{_cache}->equals(@_);
}

sub get {
    my $this = shift;
    return $this->{_cache}->get(@_);
}

sub set {
    my $this = shift;
    return $this->{_cache}->set(@_);
}

sub size {
    my $this = shift;
    return $this->{_cache}->size(@_);
}

sub remove {
    my $this = shift;
    return $this->{_cache}->remove(@_);
}

sub search {
    my $this = shift;
    return $this->{_cache}->search(@_);
}

sub toString {
    my $this = shift;
    return $this->{_cache}->toString(@_);
}

## End of facade
######################################################################

# PRIVATE load a single topic from the given data directory.
# returns 1 if the topic was loaded successfully, 0 otherwise
sub _loadTopic {
    my ( $this, $web, $topic ) = @_;

    my ( $tom, $text ) = Foswiki::Func::readTopic( $web, $topic );
    my $standardSchema = $this->{_standardSchema};
    my $session        = $Foswiki::Plugins::SESSION;

    my $archivist = $this->{archivist};
    my $meta      = $archivist->newMap();
    $meta->set( 'name',  $topic );
    $meta->set( 'web',   $web );
    $meta->set( 'topic', $topic ) unless $standardSchema;

    # SMELL: core API
    my $time;
    if ( $session->can('getApproxRevTime') ) {
        $time = $session->getApproxRevTime( $web, $topic );
    }
    else {

        # This is here for TWiki
        $time = $session->{store}->getTopicLatestRevTime( $web, $topic );
    }
    $meta->set( '.cache_path', "$web.$topic" );
    $meta->set( '.cache_time', $time );

    my $lookup;
    my $atts;
    if ($standardSchema) {

        # Add a fast lookup table for fields. This must be present
        # for QueryAcceleratorPlugin
        $lookup = $archivist->newMap();
        $meta->set( '.fields',    $lookup );
        $meta->set( '.form_name', '' );

        # Create an empty array for the attachments. We have to have this
        # due to a deficiency in the 1.0.5 query algorithm
        $atts = $archivist->newArray();
        $meta->set( 'META:FILEATTACHMENT', $atts );
    }

    my $form;
    my $hash;

    if ( $hash = $tom->get('FORM') ) {
        my ( $formWeb, $formTopic ) =
          Foswiki::Func::normalizeWebTopicName( $web, $hash->{name} );
        $formWeb =~ s/\//./g;    # normalize the normalization
        $form = $archivist->newMap();
        $form->set( 'name', "$formWeb.$formTopic" );
        if ($standardSchema) {
            $meta->set( 'META:FORM',  $form );
            $meta->set( '.form_name', "$formWeb.$formTopic" );
        }
        else {
            $meta->set( 'form', $formTopic );
        }
        $meta->set( $formTopic, $form );
    }
    if ( $hash = $tom->get('TOPICPARENT') ) {
        if ($standardSchema) {
            my $parent = $archivist->newMap( initial => $hash );
            $meta->set( 'META:TOPICPARENT', $parent );
        }
        else {
            $meta->set( 'parent', $hash->{name} );
        }
    }
    if ( $hash = $tom->get('TOPICINFO') ) {
        my $att = $archivist->newMap( initial => $hash );
        if ($standardSchema) {
            $meta->set( 'META:TOPICINFO', $att );
        }
        else {
            $meta->set( 'info', $att );
        }
    }
    if ( $hash = $tom->get('TOPICMOVED') ) {
        my $att = $archivist->newMap( initial => $hash );
        if ($standardSchema) {
            $meta->set( 'META:TOPICMOVED', $att );
        }
        else {
            $meta->set( 'moved', $att );
        }
    }
    my @fields = $tom->find('FIELD');
    if ( scalar(@fields) ) {
        my $fields;
        if ($standardSchema) {
            $fields = $archivist->newArray();
            $meta->set( 'META:FIELD', $fields );
        }
        foreach my $field (@fields) {
            if ($standardSchema) {
                my $att = $archivist->newMap( initial => $field );
                $fields->add($att);
                $lookup->set( $field->{name}, $att );
            }
            else {
                unless ($form) {
                    $form = $archivist->newMap();
                }
                $form->set( $field->{name}, $field->{value} );
            }
        }
    }
    my @attachments = $tom->find('FILEATTACHMENT');
    foreach my $attachment (@attachments) {
        my $att = $archivist->newMap( initial => $attachment );
        if ( !$standardSchema ) {
            $atts = $meta->fastget('attachments');
            if ( !defined($atts) ) {
                $atts = $archivist->newArray();
                $meta->set( 'attachments', $atts );
            }
        }
        $atts->add($att);
    }

    my $processedText = '';
    if ( $this->can('readTopicLine') ) {
        my @lines = split( /\r?\n/, $text );
        while ( scalar(@lines) ) {
            my $line = shift(@lines);
            $text .= $this->readTopicLine( $topic, $meta, $line, \@lines );
        }
    }
    else {
        $processedText = $text;
    }

    my $tomPrefs = $session->{prefs}->loadPreferences($tom);

    # cache Set preferences
    foreach my $key ( $tomPrefs->prefs() ) {
        my $prefs;
        if ($standardSchema) {
            $prefs = $meta->fastget('META:PREFERENCE');
            if ( !defined($prefs) ) {
                $prefs = $archivist->newMap();
                $meta->set( 'META:PREFERENCE', $prefs );
            }
        }
        else {
            $prefs = $meta->fastget('preferences');
            if ( !defined($prefs) ) {
                $prefs = $archivist->newMap();
                $meta->set( 'preferences', $prefs );
            }
        }
        $prefs->set( $key, $tomPrefs->get($key) );
    }

    # cache Local preferences
    foreach my $key ( $tomPrefs->localPrefs() ) {
        my $prefs;
        if ($standardSchema) {
            $prefs = $meta->fastget('META:PREFERENCE');
            if ( !defined($prefs) ) {
                $prefs = $archivist->newMap();
                $meta->set( 'META:PREFERENCE', $prefs );
            }
        }
        else {
            $prefs = $meta->fastget('preferences');
            if ( !defined($prefs) ) {
                $prefs = $archivist->newMap();
                $meta->set( 'preferences', $prefs );
            }
        }
        $prefs->set( $key, $tomPrefs->getLocal($key) );
    }

    # cache non-standard meta
    foreach my $key ( keys %Foswiki::Meta::VALIDATE ) {
        next
          if $key =~
/^(TOPICINFO|CREATEINFO|TOPICMOVED|TOPICPARENT|FILEATTACHMENT|FORM|FIELD|PREFERENCE|VERSIONS|COMMENT)$/;
        my $validation = $Foswiki::Meta::VALIDATE{$key};

        if ( $validation->{many} ) {
            my @records = $tom->find($key);
            next unless @records;

            my $array;
            foreach my $record (@records) {
                my $map = $archivist->newMap( initial => $record );
                $array = $meta->fastget( lc($key) );
                unless ( defined($array) ) {
                    $array = $archivist->newArray();
                    $meta->set( lc($key), $array );
                }
                $array->add($map);
            }
        }
        else {
            my $record = $tom->get($key);
            next unless $record;
            my $map = $archivist->newMap( initial => $record );
            $meta->set( lc($key), $map );
        }
    }

    my $all = $tom->getEmbeddedStoreForm();

    $this->cleanUpText($processedText);
    $this->cleanUpText($all);

    $meta->set( 'text', $processedText );
    $meta->set( 'all', $all ) unless $standardSchema;

    return $meta;
}

sub cleanUpText {
    my $this = shift;

    # remove inline images as they take up a lot of RAM
    $_[0] =~ s/$INLINE_IMAGE/_IMAGE_/i;

}

=begin TML

---+++ readTopicLine($topic, $meta, $line, $lines)
   * $topic - name of the topic being read
   * $meta - reference to the hash object for this topic
   * line - the line being read
   * $lines - reference to array of remaining lines after the current line
The function may modify $lines to cause the caller to skip lines.
=cut

#sub readTopicLine {
#    my ( $this, $topic, $meta, $line, $data ) = @_;
#}

=begin TML

---+++ onReload($topics)
   * =$topics= - perl array of topic names that have just been loaded (or reloaded)
Designed to be overridden by subclasses. Called when one or more topics had to be
read from disc rather than from the cache. Passed a list of topic names that have been read.

=cut

sub onReload {

    #my ( $this, @$topics) = @_;
}

sub _onReload {
    my $this = shift;

    unless ( $this->{_standardSchema} ) {
        foreach my $topic ( $this->{_cache}->getValues() ) {
            next unless $topic;    # SMELL: why does that sometimes happen?

            # Fill in parent relations
            unless ( $topic->FETCH('parent') ) {
                $topic->set( 'parent', $Foswiki::cfg{HomeTopicName} );

                # last parent is WebHome
            }
        }
    }

    $this->onReload(@_);
}

=begin TML

---+++ load( [updateCache]  ) -> ($readFromCache, $readFromFile, $removed)

Load the web into the database.
Returns a list containing 3 numbers that give the number of topics
read from the cache, the number read from file, and the number of previously
cached topics that have been removed.

=cut

sub load {
    my $this = shift;
    my $updateCache = shift || 0;

    #print STDERR "Called load($updateCache)\n";
    $this->{_cache} = undef if $updateCache;

    return ( 0, 0, 0 ) if ( $this->{_cache} );    # already loaded?

    my $web = $this->{_web};
    $web =~ s/\//\./g;

    $this->{_cache} = $this->{archivist}->getRoot();

    ASSERT( $this->{_cache} ) if DEBUG;

    # Check what's there already
    my $readFromCache = $this->{_cache}->size();
    my $readFromFile  = 0;
    my $removed       = 0;

    if ( $updateCache || $readFromCache == 0 ) {
        eval {
            ( $readFromCache, $readFromFile, $removed ) =
              $this->_updateCache($web);
        };

        if ($@) {
            print STDERR "Cache read failed $@...\n";    # if DEBUG;
            ASSERT( 0, $@ ) if DEBUG;
            Foswiki::Func::writeWarning("DBCache: Cache read failed: $@");

        }
        elsif ( $readFromFile || $removed ) {
            $this->{archivist}->sync( $this->{_cache} );
        }
    }

#print STDERR "DBCacheContrib: Loaded $readFromCache from cache, $readFromFile from file, $removed removed\n";

    return ( $readFromCache, $readFromFile, $removed );
}

sub loadTopic {
    my ( $this, $web, $topic ) = @_;

    #print STDERR "loadTopic($web, $topic)\n";
    my $found = 0;

    eval { $found = $this->_updateTopic( $web, $topic ); };

    if ($@) {
        ASSERT( 0, $@ ) if DEBUG;
        print STDERR "Cache read failed $@...\n" if DEBUG;
        Foswiki::Func::writeWarning("DBCache: Cache read failed: $@");

        $found = 0;
    }

    if ($found) {

        # refresh relations
        $this->_onReload( [$topic] );
        $this->{archivist}->sync( $this->{_cache} );
    }
}

# PRIVATE update the cache for the specific topic only
# optionally track read information, see _updateCache
sub _updateTopic {
    my ( $this, $web, $topic, $readInfo ) = @_;

    my $found = 0;

    my $topcache = $this->{_cache}->FETCH($topic);
    if (
        $topcache
        && !uptodate(
            $topcache->FETCH('.cache_path'),
            $topcache->FETCH('.cache_time')
        )
      )
    {

        #print STDERR "$web.$topic is out of date\n";
        $this->{_cache}->remove($topic);
        $$readInfo[0]-- if $readInfo;
        $topcache = undef;
    }
    if ( !$topcache ) {

        #print STDERR "$web.$topic is not in the cache\n";
        # Not in cache
        if ( Foswiki::Func::topicExists( $web, $topic ) ) {
            $topcache = $this->_loadTopic( $web, $topic );
            $this->{_cache}->set( $topic, $topcache );
        }
        else {
            $$readInfo[2]++ if $readInfo;
            $found = 1;
        }
        if ($topcache) {
            $$readInfo[1]++ if $readInfo;
            $found = 1;
        }
    }
    $topcache->set( '.fresh', 1 ) if $topcache;

    return $found;
}

# PRIVATE update the cache from files
# return the number of files changed in a tuple
sub _updateCache {
    my ( $this, $web ) = @_;

    my @readInfo = (
        0,    # read from cache
        0,    # read from file
        0,    # removed
    );

    $readInfo[0] = $this->{_cache}->size();
    foreach my $cached ( $this->{_cache}->getValues() ) {
        next unless $cached;    # SMELL: why does that happen sometimes
        $cached->set( '.fresh', 0 );
    }

    my @readTopic;

    $web =~ s/\./\//g;

    #print STDERR "_updateCache for $web\n";

    # load topics that are missing from the cache
    foreach my $topic ( Foswiki::Func::getTopicList($web) ) {
        if ( $this->_updateTopic( $web, $topic, \@readInfo ) ) {

            #print STDERR "... updated topic $web.$topic\n";
            push( @readTopic, $topic );
        }

        #don't disadvantage users just because the cache is off
        #don't disadvantage users just because the cache is off
        last
          if defined( $Foswiki::cfg{DBCacheContrib}{LoadFileLimit} )
          && ( $Foswiki::cfg{DBCacheContrib}{LoadFileLimit} > 0 )
          && ( $readInfo[1] > $Foswiki::cfg{DBCacheContrib}{LoadFileLimit} );
    }

    # Find smelly topics in the cache
    foreach my $cached ( $this->{_cache}->getValues() ) {
        next unless $cached;    # SMELL: why does that happen sometimes
        if ( $cached->FETCH('.fresh') ) {
            $cached->remove('.fresh');
        }
        else {
            $this->{_cache}->remove( $cached->FETCH('name') );
            $readInfo[0]--;
            $readInfo[2]++;
        }
    }

    if ( $readInfo[1] || $readInfo[2] ) {

        # refresh relations
        $this->_onReload( \@readTopic );
    }

    return @readInfo;
}

=begin TML

---+++ =uptodate($topic, $time)= -> boolean
Check the file time against what is seen on disc. Return 1 if consistent, 0 if inconsistent.

=cut

sub uptodate {
    my ( $path, $time ) = @_;

    $path =~ m/^(.*)\.(.*?)$/;
    my $web   = $1;
    my $topic = $2;

    $web =~ s/\./\//g;

    ASSERT( $web,   $path ) if DEBUG;
    ASSERT( $topic, $path ) if DEBUG;

    # SMELL: core API
    my $fileTime;
    if ( $Foswiki::Plugins::SESSION->{store}->can('getApproxRevTime') ) {
        $fileTime =
          $Foswiki::Plugins::SESSION->{store}->getApproxRevTime( $web, $topic );
    }
    else {

        # This is here for TWiki
        $fileTime =
          $Foswiki::Plugins::SESSION->{store}
          ->getTopicLatestRevTime( $web, $topic );
    }

    return ( $fileTime == $time ) ? 1 : 0;
}

1;
__END__

Copyright (C) Crawford Currie 2004-2017, http://c-dot.co.uk
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
