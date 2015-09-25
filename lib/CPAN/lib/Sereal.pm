package Sereal;
use 5.008;
use strict;
use warnings;
our $VERSION    = '3.00';
our $XS_VERSION = $VERSION;
$VERSION = eval $VERSION;
use Sereal::Encoder qw(encode_sereal sereal_encode_with_object);
use Sereal::Decoder
  qw(decode_sereal looks_like_sereal sereal_decode_with_object);

use Exporter 'import';
our @EXPORT_OK = qw(
  encode_sereal decode_sereal
  looks_like_sereal
  sereal_encode_with_object
  sereal_decode_with_object
);
our %EXPORT_TAGS = ( all => \@EXPORT_OK );

# export by default if run from command line
our @EXPORT = ( ( caller() )[1] eq '-e' ? @EXPORT_OK : () );

1;
