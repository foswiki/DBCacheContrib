package Foswiki::Contrib::DBCacheContrib::Archivist::SharedMemory;
use strict;
use warnings;

use Foswiki::Contrib::DBCacheContrib::MemArchivist ();
our @ISA = ('Foswiki::Contrib::DBCacheContrib::MemArchivist');

use IPC::SharedCache ();

sub clear {
    my $this = shift;
    unlink( $this->{_file} );
    undef $this->{root};
}

sub DESTROY {
    my $this = shift;
    undef $this->{root};
}

sub sync {
    my ($this) = @_;

    # Clear the archivist to avoid having pointers in the Storable
    $this->{root}->setArchivist(undef) if $this->{root};
    Storable::lock_store( $this->getRoot(), $this->{_file} );
    $this->{root}->setArchivist($this) if $this->{root};
}

sub getRoot {
    my ($this) = @_;
    unless ( $this->{root} ) {
        tie %{ $this->{root} }, 'IPC::SharedCache',
          ipc_key           => 'DBCA',
          load_callback     => sub { return $this->loadCache(@_); },
          validate_callback => sub { return $this->validateCache(@_) };

        $this->{root}->setArchivist($this);
    }
    return $this->{root};
}

sub loadCache {
    my $key = shift;
}

1;
