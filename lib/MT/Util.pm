# Movable Type (r) Open Source (C) 2001-2010 Six Apart, Ltd.
# This program is distributed under the terms of the
# GNU General Public License, version 2.
#
# $Id$

package MT::Util;

use strict;
use base 'Exporter';

use Time::Local qw( timegm );

our @EXPORT_OK
  = qw( start_end_day start_end_week start_end_month start_end_year
  start_end_period week2ymd munge_comment
  rich_text_transform html_text_transform encode_html decode_html
  iso2ts ts2iso offset_time offset_time_list first_n_words
  archive_file_for format_ts dirify remove_html
  days_in wday_from_ts encode_js get_entry spam_protect
  is_valid_email encode_php encode_url decode_url encode_xml
  decode_xml is_valid_url is_url discover_tb convert_high_ascii
  mark_odd_rows dsa_verify perl_sha1_digest relative_date
  perl_sha1_digest_hex dec2bin bin2dec xliterate_utf8
  start_background_task launch_background_tasks substr_wref
  extract_urls extract_domain extract_domains is_valid_date
  epoch2ts ts2epoch escape_unicode unescape_unicode
  sax_parser trim ltrim rtrim asset_cleanup caturl multi_iter
  weaken log_time make_string_csv sanitize_embed
  browser_language encode_json deep_do deep_copy);

{
    my $Has_Weaken;

    sub weaken {
        no warnings;
        my $disable_cache = MT->instance->config('DisableObjectCache');

        return if $disable_cache;
        if ( !$disable_cache && UNIVERSAL::isa( $_[0], 'MT::Object' ) ) {
            if ( my $props = $_[0]->properties ) {
                return
                  if ( defined $props->{cacheable} )
                  && ( !$props->{cacheable} );
            }
        }

        return Scalar::Util::weaken( $_[0] ) if $Has_Weaken;
        $Has_Weaken
          = eval 'use Scalar::Util; 1' && Scalar::Util->can('weaken') ? 1 : 0;
        Scalar::Util::weaken( $_[0] ) if $Has_Weaken;
    }
}

sub leap_day {
    my ( $y, $m, $d ) = @_;
    return
         $m == 2
      && $d == 29
      && ( $y % 4 == 0 )
      && ( $y % 100 != 0 || $y % 400 == 0 );
}

sub leap_year {
    my $y = shift;
    return ( $y % 4 == 0 ) && ( $y % 100 != 0 || $y % 400 == 0 );
}

{
    my @In_Year = ( [
                       0,   31,  59,  90,  120, 151, 181, 212,
                       243, 273, 304, 334, 365
                    ],
                    [
                       0,   31,  60,  91,  121, 152, 182, 213,
                       244, 274, 305, 335, 366
                    ],
    );

    sub wday_from_ts {
        my ( $y, $m, $d ) = @_;
        my $leap = leap_year($y) ? 1 : 0;
        $y--;

        ## Copied from Date::Calc.
        my $days = $y * 365;
        $days += $y >>= 2;
        $days -= int( $y /= 25 );
        $days += $y >> 2;
        $days += $In_Year[$leap][ $m - 1 ] + $d;
        $days % 7;
    }

    sub yday_from_ts {
        my ( $y, $m, $d ) = @_;
        my $leap = $y % 4 == 0 && ( $y % 100 != 0 || $y % 400 == 0 ) ? 1 : 0;
        $In_Year[$leap][ $m - 1 ] + $d;
    }
}

sub iso2ts {
    my ( $blog, $iso ) = @_;
    return undef
      unless $iso
          =~ /^(\d{4})(?:-?(\d{2})(?:-?(\d\d?)(?:T(\d{2}):(\d{2}):(\d{2})(?:\.\d+)?(Z|[+-]\d{2}:\d{2})?)?)?)?/;
    my ( $y, $mo, $d, $h, $m, $s, $offset )
      = ( $1, $2 || 1, $3 || 1, $4 || 0, $5 || 0, $6 || 0, $7 );
    if ( $offset && !MT->config->IgnoreISOTimezones ) {
        $mo--;
        my $time = Time::Local::timegm_nocheck( $s, $m, $h, $d, $mo, $y );
        ## If it's not already in UTC, first convert to UTC.
        if ( $offset ne 'Z' ) {
            my ( $sign, $h, $m ) = $offset =~ /([+-])(\d{2}):(\d{2})/;
            $offset = $h * 3600 + $m * 60;
            $offset *= -1 if $sign eq '-';
            $time -= $offset;
        }
        ## Now apply the offset for this weblog.
        ( $s, $m, $h, $d, $mo, $y ) = offset_time_list( $time, $blog );
        $mo++;
        $y += 1900;
    }
    sprintf "%04d%02d%02d%02d%02d%02d", $y, $mo, $d, $h, $m, $s;
} ## end sub iso2ts

sub ts2iso {
    my ( $blog, $ts ) = @_;
    my ( $yr, $mo, $dy, $hr, $mn, $sc ) = unpack( 'A4A2A2A2A2A2', $ts );
    $ts = Time::Local::timegm_nocheck( $sc, $mn, $hr, $dy, $mo - 1, $yr );
    ( $sc, $mn, $hr, $dy, $mo, $yr ) = offset_time_list( $ts, $blog, '-' );
    $yr += 1900;
    $mo += 1;
    sprintf( "%04d-%02d-%02dT%02d:%02d:%02dZ", $yr, $mo, $dy, $hr, $mn, $sc );
}

sub ts2epoch {
    my ( $blog, $ts ) = @_;
    return unless $ts;
    my ( $yr, $mo, $dy, $hr, $mn, $sc ) = unpack( 'A4A2A2A2A2A2', $ts );
    my $epoch
      = Time::Local::timegm_nocheck( $sc, $mn, $hr, $dy, $mo - 1, $yr );
    return unless $epoch;
    $epoch = offset_time( $epoch, $blog, '-' ) if ref $blog;
    $epoch;
}

sub epoch2ts {
    my ( $blog, $epoch ) = @_;
    $epoch = offset_time( $epoch, $blog ) if defined $blog;
    my ( $s, $m, $h, $d, $mo, $y ) = gmtime($epoch);
    sprintf( "%04d%02d%02d%02d%02d%02d", $y + 1900, $mo + 1, $d, $h, $m, $s );
}

# substring treating HTML character-entity references as single characters
sub substr_wref {
    my ( $str, $start, $width ) = @_;
    return '' if $start < 0;
    my @ent = $str =~ /(&[^;]*;|.)/g;
    return '' if ( $#ent < $start );
    $width = $#ent - $start + 1 if $start + $width > $#ent;
    join '', @ent[ $start .. $start + $width - 1 ];
}

sub relative_date {
    my ( $ts1, $ts2, $blog, $fmt, $style ) = @_;

    $style ||= 1;

    # TBD: Fix this
    my $ts = $ts1;
    $ts1 = ts2epoch( $blog, $ts1 );
    return unless $ts1;

    my $future = 0;
    my $delta  = $ts2 - $ts1;
    if ( $delta < 0 ) {
        $future = 1;
        $delta  = $ts1 - $ts2;
    }
    if ( $style == 1 ) {
        if ( $delta <= 60 ) {
            return $future
              ? MT->translate("moments from now")
              : MT->translate("moments ago");
        }
        elsif ( $delta <= 86400 ) {

            # less than 1 day
            my $hours = int( $delta / 3600 );
            my $min = int( ( $delta % 3600 ) / 60 );
            if ($hours) {
                return $future
                  ? MT->translate( "[quant,_1,hour,hours] from now",
                                   $hours, $min )
                  : MT->translate( "[quant,_1,hour,hours] ago", $hours,
                                   $min );
            }
            else {
                return $future
                  ? MT->translate( "[quant,_1,minute,minutes] from now",
                                   $min )
                  : MT->translate( "[quant,_1,minute,minutes] ago", $min );
            }
        }
        elsif ( $delta <= 604800 ) {

            # less than 1 week
            my $days = int( $delta / 86400 );
            my $hours = int( ( $delta % 86400 ) / 3600 );
            my $result;
            if ($days) {
                return $future
                  ? MT->translate( "[quant,_1,day,days] from now",
                                   $days, $hours )
                  : MT->translate( "[quant,_1,day,days] ago", $days, $hours );
            }
            else {
                return $future
                  ? MT->translate( "[quant,_1,hour,hours] from now", $hours )
                  : MT->translate( "[quant,_1,hour,hours] ago",      $hours );
            }
        }
        else {

            # more than a week, same year
            if ( ( localtime($ts1) )[5] == ( localtime($ts2) )[5] ) {
                $fmt ||= "%b %e";
            }
            else {
                $fmt ||= "%b %e %Y";
            }
        }
    } ## end if ( $style == 1 )
    elsif ( $style == 2 ) {
        if ( $delta <= 60 ) {
            return $future
              ? MT->translate("less than 1 minute from now")
              : MT->translate("less than 1 minute ago");
        }
        elsif ( $delta <= 86400 ) {

            # less than 1 day
            my $hours = int( $delta / 3600 );
            my $min = int( ( $delta % 3600 ) / 60 );
            my $result;
            if ( $hours && $min ) {
                $result = $future
                  ? MT->translate(
                    "[quant,_1,hour,hours], [quant,_2,minute,minutes] from now",
                    $hours,
                    $min
                  )
                  : MT->translate(
                       "[quant,_1,hour,hours], [quant,_2,minute,minutes] ago",
                       $hours, $min );
            }
            elsif ($hours) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,hour,hours] from now", $hours )
                  : MT->translate( "[quant,_1,hour,hours] ago",      $hours );
            }
            elsif ($min) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,minute,minutes] from now",
                                   $min )
                  : MT->translate( "[quant,_1,minute,minutes] ago", $min );
            }
            return $result;
        } ## end elsif ( $delta <= 86400 )
        elsif ( $delta <= 604800 ) {

            # less than 1 week
            my $days = int( $delta / 86400 );
            my $hours = int( ( $delta % 86400 ) / 3600 );
            my $result;
            if ( $days && $hours ) {
                $result = $future
                  ? MT->translate(
                        "[quant,_1,day,days], [quant,_2,hour,hours] from now",
                        $days, $hours )
                  : MT->translate(
                             "[quant,_1,day,days], [quant,_2,hour,hours] ago",
                             $days, $hours );
            }
            elsif ($days) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,day,days] from now", $days )
                  : MT->translate( "[quant,_1,day,days] ago",      $days );
            }
            elsif ($hours) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,hour,hours] from now", $hours )
                  : MT->translate( "[quant,_1,hour,hours] ago",      $hours );
            }
            return $result;
        } ## end elsif ( $delta <= 604800 )
    } ## end elsif ( $style == 2 )
    elsif ( $style == 3 ) {
        if ( $delta < 60 ) {
            return $future
              ? MT->translate( "[quant,_1,second,seconds] from now", $delta )
              : MT->translate( "[quant,_1,second,seconds]",          $delta );
        }
        elsif ( $delta <= 3600 ) {

            # less than 1 hour
            my $min = int( ( $delta % 3600 ) / 60 );
            my $sec = $delta % 60;
            my $result;
            if ( $sec && $min ) {
                $result = $future
                  ? MT->translate(
                    "[quant,_1,minute,minutes], [quant,_2,second,seconds] from now",
                    $min,
                    $sec
                  )
                  : MT->translate(
                       "[quant,_1,minute,minutes], [quant,_2,second,seconds]",
                       $min, $sec );
            }
            elsif ($min) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,minute,minutes] from now",
                                   $min )
                  : MT->translate( "[quant,_1,minute,minutes]", $min );
            }
            elsif ($sec) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,second,seconds] from now",
                                   $sec )
                  : MT->translate( "[quant,_1,second,seconds]", $sec );
            }
            return $result;
        } ## end elsif ( $delta <= 3600 )
        elsif ( $delta <= 86400 ) {

            # less than 1 day
            my $hours = int( $delta / 3600 );
            my $min = int( ( $delta % 3600 ) / 60 );
            my $result;
            if ( $hours && $min ) {
                $result = $future
                  ? MT->translate(
                    "[quant,_1,hour,hours], [quant,_2,minute,minutes] from now",
                    $hours,
                    $min
                  )
                  : MT->translate(
                           "[quant,_1,hour,hours], [quant,_2,minute,minutes]",
                           $hours, $min );
            }
            elsif ($hours) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,hour,hours] from now", $hours )
                  : MT->translate( "[quant,_1,hour,hours]",          $hours );
            }
            elsif ($min) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,minute,minutes] from now",
                                   $min )
                  : MT->translate( "[quant,_1,minute,minutes]", $min );
            }
            return $result;
        } ## end elsif ( $delta <= 86400 )
        elsif ( $delta <= 604800 ) {

            # less than 1 week
            my $days = int( $delta / 86400 );
            my $hours = int( ( $delta % 86400 ) / 3600 );
            my $result;
            if ( $days && $hours ) {
                $result = $future
                  ? MT->translate(
                        "[quant,_1,day,days], [quant,_2,hour,hours] from now",
                        $days, $hours )
                  : MT->translate(
                                 "[quant,_1,day,days], [quant,_2,hour,hours]",
                                 $days, $hours );
            }
            elsif ($days) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,day,days] from now", $days )
                  : MT->translate( "[quant,_1,day,days]",          $days );
            }
            elsif ($hours) {
                $result
                  = $future
                  ? MT->translate( "[quant,_1,hour,hours] from now", $hours )
                  : MT->translate( "[quant,_1,hour,hours]",          $hours );
            }
            return $result;
        } ## end elsif ( $delta <= 604800 )
    } ## end elsif ( $style == 3 )
    my $mt = MT->instance;
    my $user = $mt->user if $mt->isa('MT::App');
    return $fmt
      ? format_ts( $fmt, $ts, $blog,
                   $user ? $user->preferred_language : undef )
      : "";
} ## end sub relative_date

our %Languages;

sub format_ts {
    my ( $format, $ts, $blog, $lang, $is_mail ) = @_;
    return '' unless defined $ts;
    my %f;
    unless ($lang) {
        $lang = $blog
          && $blog->language ? $blog->language : MT->config->DefaultLanguage;
    }
    if ( $lang eq 'jp' ) {
        $lang = 'ja';
    }
    unless ( defined $format ) {
        $format = $Languages{$lang}[3] || "%B %e, %Y %l:%M %p";
    }
    my $cache = MT->request->cache('formats');
    unless ($cache) {
        MT::Request->instance->cache( 'formats', $cache = {} );
    }
    if ( my $f_ref = $cache->{ $ts . $lang } ) {
        %f = %$f_ref;
    }
    else {
        my $L = $Languages{$lang};
        my @ts = @f{qw( Y m d H M S )} = unpack 'A4A2A2A2A2A2', $ts;
        $f{w} = wday_from_ts( @ts[ 0 .. 2 ] );
        $f{j} = yday_from_ts( @ts[ 0 .. 2 ] );
        $f{'y'} = substr $f{Y}, 2;
        $f{b} = substr_wref $L->[1][ $f{'m'} - 1 ] || '', 0, 3;
        $f{B} = $L->[1][ $f{'m'} - 1 ];
        if ( $lang eq 'ja' ) {
            $f{a} = substr $L->[0][ $f{w} ] || '', 0, 8;
        }
        else {
            $f{a} = substr_wref $L->[0][ $f{w} ] || '', 0, 3;
        }
        $f{A} = $L->[0][ $f{w} ];
        ( $f{e} = $f{d} ) =~ s!^0! !;
        $f{I} = $f{H};
        if ( $f{I} > 12 ) {
            $f{I} -= 12;
            $f{p} = $L->[2][1];
        }
        elsif ( $f{I} == 0 ) {
            $f{I} = 12;
            $f{p} = $L->[2][0];
        }
        elsif ( $f{I} == 12 ) {
            $f{p} = $L->[2][1];
        }
        else {
            $f{p} = $L->[2][0];
        }
        $f{I} = sprintf "%02d", $f{I};
        ( $f{k} = $f{H} ) =~ s!^0! !;
        ( $f{l} = $f{I} ) =~ s!^0! !;
        $f{j}                   = sprintf "%03d", $f{j};
        $f{Z}                   = '';
        $cache->{ $ts . $lang } = \%f;
    } ## end else [ if ( my $f_ref = $cache...)]
    my $date_format = $Languages{$lang}->[4] || "%B %e, %Y";
    my $time_format = $Languages{$lang}->[5] || "%l:%M %p";
    $format =~ s!%x!$date_format!g;
    $format =~ s!%X!$time_format!g;
    ## This is a dreadful hack. I can't think of a good format specifier
    ## for "%B %Y" (which is used for monthly archives, for example) so
    ## I'll just hardcode this, for Japanese dates.
    if ( $lang eq 'ja' ) {
        $format =~ s!%B %Y!$Languages{$lang}->[6]!g;
        $format =~ s!%B %E,? %Y!$Languages{$lang}->[4]!ig;
        $format =~ s!%b. %e, %Y!$Languages{$lang}->[4]!ig;
        $format =~ s!%B %E!$Languages{$lang}->[7]!ig;
    }
    elsif ( $lang eq 'it' ) {
        ## Hack for the Italian dates
        ## In Italian, the date always come before the month.
        $format =~ s!%b %e!%e %b!g;
    }
    $format =~ s!%(\w)!$f{$1}!g if defined $format;

    if ($is_mail) {
        $format =~ s!&#([0-9]+);!chr($1)!ge;
        $format =~ s!&#[xX]([0-9A-Fa-f]+);!chr(hex $1)!ge;

        require MT::I18N;
        my $enc = MT->config->PublishCharset;
        $format = MT::I18N::encode_text( $format, undef,   'utf-8' );
        $format = MT::I18N::encode_text( $format, 'utf-8', $enc )
          unless 'utf-8' eq lc $enc;
    }
    $format;
} ## end sub format_ts

{
    my @Days_In = ( -1, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 );

    sub days_in {
        my ( $m, $y ) = @_;
        return $Days_In[$m] unless $m == 2;
        return $y % 4 == 0 && ( $y % 100 != 0 || $y % 400 == 0 ) ? 29 : 28;
    }
}

sub start_end_period {
    my $at = shift;
    if ( $at eq 'Individual' ) {
        return $_[0];
    }
    elsif ( $at eq 'Daily' ) {
        return start_end_day(@_);
    }
    elsif ( $at eq 'Weekly' ) {
        return start_end_week(@_);
    }
    elsif ( $at eq 'Monthly' ) {
        return start_end_month(@_);
    }
}

sub start_end_day {
    my $day = substr $_[0], 0, 8;
    return $day . '000000' unless wantarray;
    ( $day . "000000", $day . "235959" );
}

sub start_end_week {
    my ($ts) = @_;
    my ( $y, $mo, $d, $h, $m, $s ) = unpack 'A4A2A2A2A2A2', $ts;
    my $wday = wday_from_ts( $y, $mo, $d );
    my ( $sd, $sm, $sy ) = ( $d - $wday, $mo, $y );
    if ( $sd < 1 ) {
        $sm--;
        $sm = 12, $sy-- if $sm < 1;
        $sd += days_in( $sm, $sy );
    }
    my $start = sprintf "%04d%02d%02d%s", $sy, $sm, $sd, "000000";
    return $start unless wantarray;
    my ( $ed, $em, $ey ) = ( $d + 6 - $wday, $mo, $y );
    if ( $ed > days_in( $em, $ey ) ) {
        $ed -= days_in( $em, $ey );
        $em++;
        $em = 1, $ey++ if $em > 12;
    }
    my $end = sprintf "%04d%02d%02d%s", $ey, $em, $ed, "235959";
    ( $start, $end );
} ## end sub start_end_week

sub is_leap_year {
    ( !( $_[0] % 4 ) && ( $_[0] % 100 ) ) || !( $_[0] % 400 );
}

my @prev_month_doy
  = ( 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 );
my @prev_month_doly
  = ( 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335 );

sub week2ymd {
    my ( $y, $week ) = @_;
    require MT::DateTime;
    my $jan_one_dow_m1 = ( MT::DateTime->ymd2rd( $y, 1, 1 ) + 6 ) % 7;
    ( $y, $week ) = unpack 'A4A2', $week if $week > $y;
    $week-- if $jan_one_dow_m1 < 4;
    my $day_of_year = $week * 7 - $jan_one_dow_m1;
    my $leap_year   = is_leap_year($y);
    if ( $day_of_year < 1 ) {
        $y--;
        $day_of_year = ( $leap_year ? 366 : 365 ) + $day_of_year;
    }
    my $ref = $leap_year ? \@prev_month_doly : \@prev_month_doy;
    my $m;
    my $i = @$ref;
    for my $days ( reverse @$ref ) {
        if ( $day_of_year > $days ) {
            $m = $i;
            last;
        }
        $i--;
    }
    ( $y, $m, $day_of_year - $ref->[ $m - 1 ] );
} ## end sub week2ymd

sub start_end_month {
    my ($ts) = @_;
    my ( $y, $mo ) = unpack 'A4A2', $ts;
    my $start = sprintf "%04d%02d01000000", $y, $mo;
    return $start unless wantarray;
    my $end = sprintf "%04d%02d%02d235959", $y, $mo, days_in( $mo, $y );
    ( $start, $end );
}

sub start_end_year {
    my ($ts) = @_;
    my ($y) = unpack 'A4', $ts;
    my $start = sprintf "%04d0101000000", $y;
    return $start unless wantarray;
    my $end = sprintf "%04d1231235959", $y;
    ( $start, $end );
}

sub offset_time_list { gmtime offset_time(@_) }

sub offset_time {
    my ( $ts, $blog, $dir ) = @_;
    my $offset;
    if ( defined $blog ) {
        if ( !ref($blog) ) {
            require MT::Blog;
            $blog = MT::Blog->load($blog);
        }
        $offset = $blog && $blog->server_offset ? $blog->server_offset : 0;
    }
    else {
        $offset = MT->config->TimeOffset;
    }
    $offset += 1 if $blog && ( localtime $ts )[8];
    $offset *= -1 if $dir && $dir eq '-';
    $ts += $offset * 3600;
    $ts;
}

sub rich_text_transform {
    my $str = shift;
    return $str;
}

sub html_text_transform {
    my $str = shift;
    $str = '' unless defined $str;
    my @paras = split /\r?\n\r?\n/, $str;
    for my $p (@paras) {
        if ( $p
            !~ m@^</?(?:h1|h2|h3|h4|h5|h6|table|ol|dl|ul|menu|dir|p|pre|center|form|fieldset|select|blockquote|address|div|hr)@
          )
        {
            $p =~ s!\r?\n!<br />\n!g;
            $p = "<p>$p</p>";
        }
    }
    join "\n\n", @paras;
}

{
    my %Map = ( ':' => '&#58;', '@' => '&#64;', '.' => '&#46;' );

    sub spam_protect {
        my ($str) = @_;
        my $look = join '', keys %Map;
        $str =~ s!([$look])!$Map{$1}!g;
        $str;
    }
}

sub encode_js {
    my ($str) = @_;
    return '' unless defined $str;
    $str =~ s!\\!\\\\!g;
    $str =~ s!>!\\>!g;
    $str =~ s!<!\\<!g;
    $str =~ s!(s)(cript)!$1\\$2!gi;
    $str =~ s!</!<\\/!g
      ;    # </ is supposed to be the end of Javascript (</script in most UA)
    $str =~ s!(['"])!\\$1!g;
    $str =~ s!\n!\\n!g;
    $str =~ s!\0!\\0!g;
    $str =~ s!\f!\\f!g;
    $str =~ s!\r!\\r!g;
    $str =~ s!\t!\\t!g;
    $str;
}

sub encode_json {
    my ($str) = @_;
    return '' unless defined $str;
    $str =~ s!\\!\\\\!g;    # \
    $str =~ s!\/!\\\/!g;    # /
    $str =~ s!"!\\"!g;      # "
    $str =~ s!\f!\\f!g;     # \f
    $str =~ s!\n!\\n!g;     # \n
    $str =~ s!\r!\\r!g;     # \r
    $str =~ s!\t!\\t!g;     # \t
    $str =~ s!\0!\\0!g;
    $str;
}

sub encode_php {
    my ( $str, $meth ) = @_;
    return '' unless defined $str;
    if ( $meth eq 'qq' ) {
        $str = encode_phphere($str);
        $str =~ s!"!\\"!g;    ## Replace " with \"
    }
    elsif ( substr( $meth, 0, 4 ) eq 'here' ) {
        $str = encode_phphere($str);
    }
    else {
        $str =~ s!\\!\\\\!g;    ## Replace \ with \\
        $str =~ s!'!\\'!g;      ## Replace ' with \'
    }
    $str;
}

sub encode_phphere {
    my ($str) = @_;
    $str =~ s!\\!\\\\!g;        ## Replace \ with \\
    $str =~ s!\$!\\\$!g;        ## Replace $ with \$
    $str =~ s!\n!\\n!g;         ## Replace character \n with string \n
    $str =~ s!\r!\\r!g;         ## Replace character \r with string \r
    $str =~ s!\t!\\t!g;         ## Replace character \t with string \t
    $str;
}

sub encode_url {
    my ($str) = @_;
    $str =~ s!([^a-zA-Z0-9_.~-])!uc sprintf "%%%02x", ord($1)!eg;
    $str;
}

sub decode_url {
    my ($str) = @_;
    $str =~ s!%([0-9a-fA-F][0-9a-fA-F])!pack("H*",$1)!eg;
    $str;
}

{
    my $Have_Entities;

    sub encode_html {
        my ( $html, $can_double_encode ) = @_;
        return '' unless defined $html;
        $html =~ tr!\cM!!d;
        unless ( defined($Have_Entities) ) {
            $Have_Entities = eval 'use HTML::Entities; 1' ? 1 : 0;
            $Have_Entities = 0
              if $Have_Entities && MT->config->NoHTMLEntities;
        }
        if ($Have_Entities) {
            $html = HTML::Entities::encode_entities($html);
        }
        else {
            if ($can_double_encode) {
                $html =~ s!&!&amp;!g;
            }
            else {
                ## Encode any & not followed by something that looks like
                ## an entity, numeric or otherwise.
                $html =~ s/&(?!#?[xX]?(?:[0-9a-fA-F]+|\w{1,8});)/&amp;/g;
            }
            $html =~ s!"!&quot;!g;    #"
            $html =~ s!<!&lt;!g;
            $html =~ s!>!&gt;!g;
        }
        return $html;
    } ## end sub encode_html

    sub decode_html {
        my ($html) = @_;
        return '' unless defined $html;
        $html =~ tr!\cM!!d;
        unless ( defined($Have_Entities) ) {
            $Have_Entities = eval 'use HTML::Entities; 1' ? 1 : 0;
            $Have_Entities = 0
              if $Have_Entities && MT->config->NoHTMLEntities;
        }
        if ($Have_Entities) {
            $html = HTML::Entities::decode_entities($html);
        }
        else {
            $html =~ s!&quot;!"!g;    #"
            $html =~ s!&lt;!<!g;
            $html =~ s!&gt;!>!g;
            $html =~ s!&amp;!&!g;
        }
        return $html;
    } ## end sub decode_html
}

{
    my %Map = (
                '&'  => '&amp;',
                '"'  => '&quot;',
                '<'  => '&lt;',
                '>'  => '&gt;',
                '\'' => '&apos;'
    );
    my %Map_Decode = reverse %Map;
    my $RE         = join '|', keys %Map;
    my $RE_D       = join '|', keys %Map_Decode;

    sub encode_xml {
        my ( $str, $nocdata ) = @_;
        return '' unless defined $str;
        $nocdata ||= MT->config->NoCDATA;
        if (
              !$nocdata
            && $str =~ m/
            <[^>]+>  ## HTML markup
            |        ## or
            &(?:(?!(\#([0-9]+)|\#x([0-9a-fA-F]+))).*?);
                     ## something that looks like an HTML entity.
        /x
          )
        {
            ## If ]]> exists in the string, encode the > to &gt;.
            $str =~ s/]]>/]]&gt;/g;
            $str = '<![CDATA[' . $str . ']]>';
        }
        else {
            $str =~ s!($RE)!$Map{$1}!g;

            # re-replace &amp;#nnnn => &#nnnn
            $str =~ s/&amp;((\#([0-9]+)|\#x([0-9a-fA-F]+)).*?);/&$1;/g;
        }
        $str;
    } ## end sub encode_xml

    sub decode_xml {
        my ($str) = @_;
        return '' unless defined $str;
        if ( $str =~ s/<!\[CDATA\[(.*?)]]>/$1/g ) {
            ## Decode encoded ]]&gt;
            $str =~ s/]]&(gt|#62);/]]>/g;
        }
        else {
            $str =~ s!($RE_D)!$Map_Decode{$1}!g;
        }
        $str;
    }
}

sub remove_html {
    my ($text) = @_;
    return '' if !defined $text;    # suppress warnings
    $text =~ s/(<\!\[CDATA\[(.*?)\]\]>)|(<(?!\?)[^>]+>)/
        defined $1 ? $1 : ''
        /geisx;
    $text =~ s/<(?!\!\[CDATA\[)/&lt;/gis;

    return $text;
}

sub iso_dirify {
    my $s = $_[0];
    return '' unless defined $s;
    my $sep;
    if ( ( defined $_[1] ) && ( $_[1] ne '1' ) ) {
        $sep = $_[1];
    }
    else {
        $sep = '_';
    }
    $s = convert_high_ascii($s);    ## convert high-ASCII chars to 7bit.
    $s = lc $s;                     ## lower-case.
    $s = remove_html($s);           ## remove HTML tags.
    $s =~ s!&[^;\s]+;!!gs;          ## remove HTML entities.
    $s =~ s![^\w\s-]!!gs;           ## remove non-word/space chars.
    $s =~ s!\s+!$sep!gs;            ## change space chars to underscores.
    $s =~ s!([_-]){2,}!$sep!gs;     ## compact 2 or more hypens or underscores
    $s;
}

sub utf8_dirify {
    my $s = $_[0];
    return '' unless defined $s;
    my $sep;
    if ( ( defined $_[1] ) && ( $_[1] ne '1' ) ) {
        $sep = $_[1];
    }
    else {
        $sep = '_';
    }
    $s = xliterate_utf8($s);    ## convert two-byte UTF-8 chars to 7bit ASCII
    $s = lc $s;                 ## lower-case.
    $s = remove_html($s);       ## remove HTML tags.
    $s =~ s!&[^;\s]+;!!gs;      ## remove HTML entities.
    $s =~ s![^\w\s-]!!gs;       ## remove non-word/space chars.
    $s =~ s!\s+!$sep!gs;        ## change space chars to underscores.
    $s =~ s!([_-]){2,}!$sep!gs; ## compact 2 or more hypens or underscores
    $s;
}

sub dirify {
    ( $MT::VERSION && MT->instance->{cfg}->PublishCharset =~ m/utf-?8/i )
      ? utf8_dirify(@_) : iso_dirify(@_);
}

sub convert_high_ascii {
    require MT::I18N;
    MT::I18N::convert_high_ascii(@_);
}

sub xliterate_utf8 {
    my ($str) = @_;
    my %utf8_table = (
         "\xc3\x80" => 'A',      # A`
         "\xc3\xa0" => 'a',      # a`
         "\xc3\x81" => 'A',      # A'
         "\xc3\xa1" => 'a',      # a'
         "\xc3\x82" => 'A',      # A^
         "\xc3\xa2" => 'a',      # a^
         "\xc4\x82" => 'A',      # latin capital letter a with breve
         "\xc4\x83" => 'a',      # latin small letter a with breve
         "\xc3\x86" => 'AE',     # latin capital letter AE
         "\xc3\xa6" => 'ae',     # latin small letter ae
         "\xc3\x85" => 'A',      # latin capital letter a with ring above
         "\xc3\xa5" => 'a',      # latin small letter a with ring above
         "\xc4\x80" => 'A',      # latin capital letter a with macron
         "\xc4\x81" => 'a',      # latin small letter a with macron
         "\xc4\x84" => 'A',      # latin capital letter a with ogonek
         "\xc4\x85" => 'a',      # latin small letter a with ogonek
         "\xc3\x84" => 'A',      # A:
         "\xc3\xa4" => 'a',      # a:
         "\xc3\x83" => 'A',      # A~
         "\xc3\xa3" => 'a',      # a~
         "\xc3\x88" => 'E',      # E`
         "\xc3\xa8" => 'e',      # e`
         "\xc3\x89" => 'E',      # E'
         "\xc3\xa9" => 'e',      # e'
         "\xc3\x8a" => 'E',      # E^
         "\xc3\xaa" => 'e',      # e^
         "\xc3\x8b" => 'E',      # E:
         "\xc3\xab" => 'e',      # e:
         "\xc4\x92" => 'E',      # latin capital letter e with macron
         "\xc4\x93" => 'e',      # latin small letter e with macron
         "\xc4\x98" => 'E',      # latin capital letter e with ogonek
         "\xc4\x99" => 'e',      # latin small letter e with ogonek
         "\xc4\x9a" => 'E',      # latin capital letter e with caron
         "\xc4\x9b" => 'e',      # latin small letter e with caron
         "\xc4\x94" => 'E',      # latin capital letter e with breve
         "\xc4\x95" => 'e',      # latin small letter e with breve
         "\xc4\x96" => 'E',      # latin capital letter e with dot above
         "\xc4\x97" => 'e',      # latin small letter e with dot above
         "\xc3\x8c" => 'I',      # I`
         "\xc3\xac" => 'i',      # i`
         "\xc3\x8d" => 'I',      # I'
         "\xc3\xad" => 'i',      # i'
         "\xc3\x8e" => 'I',      # I^
         "\xc3\xae" => 'i',      # i^
         "\xc3\x8f" => 'I',      # I:
         "\xc3\xaf" => 'i',      # i:
         "\xc4\xaa" => 'I',      # latin capital letter i with macron
         "\xc4\xab" => 'i',      # latin small letter i with macron
         "\xc4\xa8" => 'I',      # latin capital letter i with tilde
         "\xc4\xa9" => 'i',      # latin small letter i with tilde
         "\xc4\xac" => 'I',      # latin capital letter i with breve
         "\xc4\xad" => 'i',      # latin small letter i with breve
         "\xc4\xae" => 'I',      # latin capital letter i with ogonek
         "\xc4\xaf" => 'i',      # latin small letter i with ogonek
         "\xc4\xb0" => 'I',      # latin capital letter with dot above
         "\xc4\xb1" => 'i',      # latin small letter dotless i
         "\xc4\xb2" => 'IJ',     # latin capital ligature ij
         "\xc4\xb3" => 'ij',     # latin small ligature ij
         "\xc4\xb4" => 'J',      # latin capital letter j with circumflex
         "\xc4\xb5" => 'j',      # latin small letter j with circumflex
         "\xc4\xb6" => 'K',      # latin capital letter k with cedilla
         "\xc4\xb7" => 'k',      # latin small letter k with cedilla
         "\xc4\xb8" => 'k',      # latin small letter kra
         "\xc5\x81" => 'L',      # latin capital letter l with stroke
         "\xc5\x82" => 'l',      # latin small letter l with stroke
         "\xc4\xbd" => 'L',      # latin capital letter l with caron
         "\xc4\xbe" => 'l',      # latin small letter l with caron
         "\xc4\xb9" => 'L',      # latin capital letter l with acute
         "\xc4\xba" => 'l',      # latin small letter l with acute
         "\xc4\xbb" => 'L',      # latin capital letter l with cedilla
         "\xc4\xbc" => 'l',      # latin small letter l with cedilla
         "\xc4\xbf" => 'l',      # latin capital letter l with middle dot
         "\xc5\x80" => 'l',      # latin small letter l with middle dot
         "\xc3\x92" => 'O',      # O`
         "\xc3\xb2" => 'o',      # o`
         "\xc3\x93" => 'O',      # O'
         "\xc3\xb3" => 'o',      # o'
         "\xc3\x94" => 'O',      # O^
         "\xc3\xb4" => 'o',      # o^
         "\xc3\x96" => 'O',      # O:
         "\xc3\xb6" => 'o',      # o:
         "\xc3\x95" => 'O',      # O~
         "\xc3\xb5" => 'o',      # o~
         "\xc3\x98" => 'O',      # O/
         "\xc3\xb8" => 'o',      # o/
         "\xc5\x8c" => 'O',      # latin capital letter o with macron
         "\xc5\x8d" => 'o',      # latin small letter o with macron
         "\xc5\x90" => 'O',      # latin capital letter o with double acute
         "\xc5\x91" => 'o',      # latin small letter o with double acute
         "\xc5\x8e" => 'O',      # latin capital letter o with breve
         "\xc5\x8f" => 'o',      # latin small letter o with breve
         "\xc5\x92" => 'OE',     # latin capital ligature oe
         "\xc5\x93" => 'oe',     # latin small ligature oe
         "\xc5\x94" => 'R',      # latin capital letter r with acute
         "\xc5\x95" => 'r',      # latin small letter r with acute
         "\xc5\x98" => 'R',      # latin capital letter r with caron
         "\xc5\x99" => 'r',      # latin small letter r with caron
         "\xc5\x96" => 'R',      # latin capital letter r with cedilla
         "\xc5\x97" => 'r',      # latin small letter r with cedilla
         "\xc3\x99" => 'U',      # U`
         "\xc3\xb9" => 'u',      # u`
         "\xc3\x9a" => 'U',      # U'
         "\xc3\xba" => 'u',      # u'
         "\xc3\x9b" => 'U',      # U^
         "\xc3\xbb" => 'u',      # u^
         "\xc3\x9c" => 'U',      # U:
         "\xc3\xbc" => 'u',      # u:
         "\xc5\xaa" => 'U',      # latin capital letter u with macron
         "\xc5\xab" => 'u',      # latin small letter u with macron
         "\xc5\xae" => 'U',      # latin capital letter u with ring above
         "\xc5\xaf" => 'u',      # latin small letter u with ring above
         "\xc5\xb0" => 'U',      # latin capital letter u with double acute
         "\xc5\xb1" => 'u',      # latin small letter u with double acute
         "\xc5\xac" => 'U',      # latin capital letter u with breve
         "\xc5\xad" => 'u',      # latin small letter u with breve
         "\xc5\xa8" => 'U',      # latin capital letter u with tilde
         "\xc5\xa9" => 'u',      # latin small letter u with tilde
         "\xc5\xb2" => 'U',      # latin capital letter u with ogonek
         "\xc5\xb3" => 'u',      # latin small letter u with ogonek
         "\xc3\x87" => 'C',      # ,C
         "\xc3\xa7" => 'c',      # ,c
         "\xc4\x86" => 'C',      # latin capital letter c with acute
         "\xc4\x87" => 'c',      # latin small letter c with acute
         "\xc4\x8c" => 'C',      # latin capital letter c with caron
         "\xc4\x8d" => 'c',      # latin small letter c with caron
         "\xc4\x88" => 'C',      # latin capital letter c with circumflex
         "\xc4\x89" => 'c',      # latin small letter c with circumflex
         "\xc4\x8a" => 'C',      # latin capital letter c with dot above
         "\xc4\x8b" => 'c',      # latin small letter c with dot above
         "\xc4\x8e" => 'D',      # latin capital letter d with caron
         "\xc4\x8f" => 'd',      # latin small letter d with caron
         "\xc4\x90" => 'D',      # latin capital letter d with stroke
         "\xc4\x91" => 'd',      # latin small letter d with stroke
         "\xc3\x91" => 'N',      # N~
         "\xc3\xb1" => 'n',      # n~
         "\xc5\x83" => 'N',      # latin capital letter n with acute
         "\xc5\x84" => 'n',      # latin small letter n with acute
         "\xc5\x87" => 'N',      # latin capital letter n with caron
         "\xc5\x88" => 'n',      # latin small letter n with caron
         "\xc5\x85" => 'N',      # latin capital letter n with cedilla
         "\xc5\x86" => 'n',      # latin small letter n with cedilla
         "\xc5\x89" => 'n',      # latin small letter n preceded by apostrophe
         "\xc5\x8a" => 'N',      # latin capital letter eng
         "\xc5\x8b" => 'n',      # latin small letter eng
         "\xc3\x9f" => 'ss',     # double-s
         "\xc5\x9a" => 'S',      # latin capital letter s with acute
         "\xc5\x9b" => 's',      # latin small letter s with acute
         "\xc5\xa0" => 'S',      # latin capital letter s with caron
         "\xc5\xa1" => 's',      # latin small letter s with caron
         "\xc5\x9e" => 'S',      # latin capital letter s with cedilla
         "\xc5\x9f" => 's',      # latin small letter s with cedilla
         "\xc5\x9c" => 'S',      # latin capital letter s with circumflex
         "\xc5\x9d" => 's',      # latin small letter s with circumflex
         "\xc8\x98" => 'S',      # latin capital letter s with comma below
         "\xc8\x99" => 's',      # latin small letter s with comma below
         "\xc5\xa4" => 'T',      # latin capital letter t with caron
         "\xc5\xa5" => 't',      # latin small letter t with caron
         "\xc5\xa2" => 'T',      # latin capital letter t with cedilla
         "\xc5\xa3" => 't',      # latin small letter t with cedilla
         "\xc5\xa6" => 'T',      # latin capital letter t with stroke
         "\xc5\xa7" => 't',      # latin small letter t with stroke
         "\xc8\x9a" => 'T',      # latin capital letter t with comma below
         "\xc8\x9b" => 't',      # latin small letter t with comma below
         "\xc6\x92" => 'f',      # latin small letter f with hook
         "\xc4\x9c" => 'G',      # latin capital letter g with circumflex
         "\xc4\x9d" => 'g',      # latin small letter g with circumflex
         "\xc4\x9e" => 'G',      # latin capital letter g with breve
         "\xc4\x9f" => 'g',      # latin small letter g with breve
         "\xc4\xa0" => 'G',      # latin capital letter g with dot above
         "\xc4\xa1" => 'g',      # latin small letter g with dot above
         "\xc4\xa2" => 'G',      # latin capital letter g with cedilla
         "\xc4\xa3" => 'g',      # latin small letter g with cedilla
         "\xc4\xa4" => 'H',      # latin capital letter h with circumflex
         "\xc4\xa5" => 'h',      # latin small letter h with circumflex
         "\xc4\xa6" => 'H',      # latin capital letter h with stroke
         "\xc4\xa7" => 'h',      # latin small letter h with stroke
         "\xc5\xb4" => 'W',      # latin capital letter w with circumflex
         "\xc5\xb5" => 'w',      # latin small letter w with circumflex
         "\xc3\x9d" => 'Y',      # latin capital letter y with acute
         "\xc3\xbd" => 'y',      # latin small letter y with acute
         "\xc5\xb8" => 'Y',      # latin capital letter y with diaeresis
         "\xc3\xbf" => 'y',      # latin small letter y with diaeresis
         "\xc5\xb6" => 'Y',      # latin capital letter y with circumflex
         "\xc5\xb7" => 'y',      # latin small letter y with circumflex
         "\xc5\xbd" => 'Z',      # latin capital letter z with caron
         "\xc5\xbe" => 'z',      # latin small letter z with caron
         "\xc5\xbb" => 'Z',      # latin capital letter z with dot above
         "\xc5\xbc" => 'z',      # latin small letter z with dot above
         "\xc5\xb9" => 'Z',      # latin capital letter z with acute
         "\xc5\xba" => 'z',      # latin small letter z with acute
         "\xd0\x81" => 'E',      # cyrillic capital letter IO
         "\xd0\x90" => 'A',      # cyrillic capital letter A
         "\xd0\x91" => 'B',      # cyrillic capital letter BE
         "\xd0\x92" => 'V',      # cyrillic capital letter VE
         "\xd0\x93" => 'G',      # cyrillic capital letter GHE
         "\xd0\x94" => 'D',      # cyrillic capital letter DE
         "\xd0\x95" => 'E',      # cyrillic capital letter IE
         "\xd0\x96" => 'Zh',     # cyrillic capital letter ZHE
         "\xd0\x97" => 'Z',      # cyrillic capital letter ZE
         "\xd0\x98" => 'I',      # cyrillic capital letter I
         "\xd0\x99" => 'J',      # cyrillic capital letter SHORT I
         "\xd0\x9a" => 'K',      # cyrillic capital letter KA
         "\xd0\x9b" => 'L',      # cyrillic capital letter EL
         "\xd0\x9c" => 'M',      # cyrillic capital letter EM
         "\xd0\x9d" => 'N',      # cyrillic capital letter EN
         "\xd0\x9e" => 'O',      # cyrillic capital letter O
         "\xd0\x9f" => 'P',      # cyrillic capital letter PE
         "\xd0\xa0" => 'R',      # cyrillic capital letter ER
         "\xd0\xa1" => 'S',      # cyrillic capital letter ES
         "\xd0\xa2" => 'T',      # cyrillic capital letter TE
         "\xd0\xa3" => 'U',      # cyrillic capital letter U
         "\xd0\xa4" => 'F',      # cyrillic capital letter EF
         "\xd0\xa5" => 'X',      # cyrillic capital letter HA
         "\xd0\xa6" => 'C',      # cyrillic capital letter TSE
         "\xd0\xa7" => 'Ch',     # cyrillic capital letter CHE
         "\xd0\xa8" => 'Sh',     # cyrillic capital letter SHA
         "\xd0\xa9" => 'Sch',    # cyrillic capital letter SHCHA
         "\xd0\xaa" => '_',      # cyrillic capital letter HARD SIGN
         "\xd0\xab" => 'I',      # cyrillic capital letter YERU
         "\xd0\xac" => '_',      # cyrillic capital letter SOFT SIGN
         "\xd0\xad" => 'E',      # cyrillic capital letter E
         "\xd0\xae" => 'Ju',     # cyrillic captial letter JU
         "\xd0\xaf" => 'Ja',     # cyrillic capital letter YA
         "\xd0\xb0" => 'a',      # cyrillic small letter A
         "\xd0\xb1" => 'b',      # cyrillic small letter BE
         "\xd0\xb2" => 'v',      # cyrillic small letter VE
         "\xd0\xb3" => 'g',      # cyrillic small letter GHE
         "\xd0\xb4" => 'd',      # cyrillic small letter DE
         "\xd0\xb5" => 'e',      # cyrillic small letter IE
         "\xd0\xb6" => 'zh',     # cyrillic small letter ZHE
         "\xd0\xb7" => 'z',      # cyrillic small letter ZE
         "\xd0\xb8" => 'i',      # cyrillic small letter I
         "\xd0\xb9" => 'j',      # cyrillic small letter SHORT I
         "\xd0\xba" => 'k',      # cyrillic small letter KA
         "\xd0\xbb" => 'l',      # cyrillic small letter EL
         "\xd0\xbc" => 'm',      # cyrillic small letter EM
         "\xd0\xbd" => 'n',      # cyrillic small letter EN
         "\xd0\xbe" => 'o',      # cyrillic small letter O
         "\xd0\xbf" => 'p',      # cyrillic small letter PE
         "\xd1\x80" => 'r',      # cyrillic small letter ER
         "\xd1\x81" => 's',      # cyrillic small letter ES
         "\xd1\x82" => 't',      # cyrillic small letter TE
         "\xd1\x83" => 'u',      # cyrillic small letter U
         "\xd1\x84" => 'f',      # cyrillic small letter EF
         "\xd1\x85" => 'x',      # cyrillic small letter HA
         "\xd1\x86" => 'c',      # cyrillic small letter TSE
         "\xd1\x87" => 'ch',     # cyrillic small letter CHE
         "\xd1\x88" => 'sh',     # cyrillic small letter SHA
         "\xd1\x89" => 'sch',    # cyrillic small letter SHCHA
         "\xd1\x8a" => '_',      # cyrillic small letter HARD SIGN
         "\xd1\x8b" => 'i',      # cyrillic small letter YERU
         "\xd1\x8c" => '_',      # cyrillic small letter SOFT SIGN
         "\xd1\x8d" => 'e',      # cyrillic small letter E
         "\xd1\x8e" => 'ju',     # cyrillic small letter YU
         "\xd1\x8f" => 'ja',     # cyrillic small letter YA
         "\xd1\x91" => 'e',      # cyrillic small letter IO
    );

    $str =~ s/([\200-\377]{2})/$utf8_table{$1}||''/ge;
    $str;
} ## end sub xliterate_utf8

sub first_n_words {
    my ( $text, $n ) = @_;
    $text = remove_html($text) || '';
    my @words = split /\s+/, $text;
    my $max = @words > $n ? $n : @words;
    return join ' ', @words[ 0 .. $max - 1 ];
}

sub munge_comment {
    my ( $text, $blog ) = @_;
    unless ( $blog->allow_comment_html ) {
        $text = remove_html($text);
    }
    if ( $blog->autolink_urls ) {
        $text =~ s!(^|\s)(https?://\S+)!$1<a href="$2">$2</a>!gs;
    }
    $text;
}

my %DynamicURIs = (
              'Individual' => 'entry/<$MTEntryID$>',
              'Weekly' => 'archives/week/<$MTArchiveDate format="%Y/%m/%d"$>',
              'Monthly'  => 'archives/<$MTArchiveDate format="%Y/%m"$>',
              'Daily'    => 'archives/<$MTArchiveDate format="%Y/%m/%d"$>',
              'Category' => 'section/<$MTCategoryID$>',
);

sub make_basename {
    my ($entry) = @_;
    my $title = $entry->title;
    $title = '' unless defined $title;
    $title = trim($title);
    if ( $title eq '' ) {
        if ( my $text = $entry->text ) {
            $title =
              MT::I18N::first_n_text(
                                      $text,
                                      MT::I18N::const(
                                               'LENGTH_ENTRY_TITLE_FROM_TEXT')
              );
        }
        $title = 'Post' if $title eq '';
    }
    my $limit = $entry->blog->basename_limit || 30;    # FIXME
    $limit = 15  if $limit < 15;
    $limit = 250 if $limit > 250;
    my $base = substr( dirify($title), 0, $limit );
    $base =~ s/_+$//;
    $base = 'post' if $base eq '';
    return $base;
} ## end sub make_basename

sub make_unique_basename {
    my ($entry) = @_;
    my $class   = ref $entry;
    my $blog    = $entry->blog;
    my $i       = 1;
    my $base = my $base_copy = make_basename($entry);
    while ( $class->exist( { blog_id => $blog->id, basename => $base } ) ) {
        $base = $base_copy . '_' . $i++;
    }
    return $base;
}

sub make_unique_category_basename {
    my ($cat) = @_;
    require MT::Blog;
    my $blog  = MT::Blog->load( $cat->blog_id );
    my $label = $cat->label;
    $label = '' if !defined $label;
    $label = trim($label);

    my $name = MT::Util::dirify($label)
      || ( $cat->basename_prefix(1) . $cat->id );

    my $limit
      = ( $blog && $blog->basename_limit ) ? $blog->basename_limit : 30;
    $limit = 15  if $limit < 15;
    $limit = 250 if $limit > 250;
    my $base = substr( $name, 0, $limit );
    $base =~ s/_+$//;
    $base = $cat->basename_prefix(0)
      if $base eq '';    #FIXME when does this happen?
    my $i         = 1;
    my $base_copy = $base;

    my $cat_class = ref $cat;
    while (
        $cat_class->exist( { blog_id => $cat->blog_id, basename => $base } ) )
    {
        $base = $base_copy . '_' . $i++;
    }
    $base;
} ## end sub make_unique_category_basename

sub make_unique_author_basename {
    my ($author) = @_;
    my $name = MT::Util::dirify( $author->nickname || '' );
    if ( !$name || ( $name !~ /\w/ ) ) {
        if ( $author->id ) {
            $name = "author" . $author->id;
        }
        else {
            require Digest::MD5;
            $name = "author"
              . substr( Digest::MD5::md5_hex( $author->name ), 0, 5 );
        }
    }

    my $limit = MT->instance->config('AuthorBasenameLimit');
    $limit = 15  if $limit < 15;
    $limit = 250 if $limit > 250;
    my $base = substr( $name, 0, $limit );
    $base =~ s/_+$//;
    my $i         = 1;
    my $base_copy = $base;

    my $author_class = ref $author;
    while ( $author_class->exist( { basename => $base } ) ) {
        $base = $base_copy . '_' . $i++;
    }
    $base;
} ## end sub make_unique_author_basename

sub archive_file_for {
    MT->instance->publisher->archive_file_for(@_);
}

sub strip_index {
    my ( $link, $blog ) = @_;
    my $index = MT->instance->config('IndexBasename');
    my $ext = $blog->file_extension || '';
    $ext = '.' . $ext if $ext ne '';
    $index .= $ext;
    if ( $link =~ /^(.*?)\/\Q$index\E(#.*)?$/ ) {
        $link = $1 . '/' . ( $2 || '' );
    }
    $link;
}

sub get_entry {
    my ( $ts, $blog_id, $at, $order ) = @_;
    my $archiver = MT->instance->publisher->archiver($at) or return;

    if ( $archiver->can('get_entry') ) {
        return $archiver->get_entry( $ts, $blog_id, $order );
    }

    return;
}

sub is_valid_date {
    my ($ts) = @_;
    unless (
        $ts =~ m!(\d{4})-?(\d{2})-?(\d{2})\s*(\d{2}):?(\d{2})(?::?(\d{2}))?! )
    {
        return 0;
    }
    my $s = $6 || 0;
    return 0
      if (    $s > 59
           || $s < 0
           || $5 > 59
           || $5 < 0
           || $4 > 23
           || $4 < 0
           || $2 > 12
           || $2 < 1
           || $3 < 1
           || ( days_in( $2, $1 ) < $3 && !leap_day( $0, $1, $2 ) ) );
    1;
} ## end sub is_valid_date

sub is_valid_email {
    my ($addr) = @_;
    return 0 if $addr =~ /[\n\r]/;
    my $specials = '\(\)<>\@,;:\[\]';
    if ( $addr
        =~ /^\s*([^\" \t\n\r$specials]+@[^ \t\n\r$specials]+\.[^ \t\n\r$specials][^ \t\n\r$specials]+)\s*$/
      )
    {
        return $1;
    }
    else {
        return 0;
    }
}

sub is_valid_url {
    my ( $url, $stringent ) = @_;

    $url ||= "";

    # strip spaces
    $url =~ s/^\s*//;
    $url =~ s/\s*$//;

    return '' if ( $url =~ /[ \"]/ );

    # help fat-finger typists.
    $url =~ s,http;//,http://,;
    $url =~ s,http//,http://,;

    $url = "http://$url" unless ( $url =~ m,https?://, );

    my ( $scheme, $host, $path, $query, $fragment )
      = $url
      =~ m,(?:([^:/?#]+):)?(?://([^/?#]*))?([^?#]*)(?:\?([^#]*))?(?:#(.*))?,;
    if ( $scheme && $host ) {

        # Note: no stringent checks; localhost is a legit hostname, for example.
        return $url;
    }
    else {
        return '';
    }
} ## end sub is_valid_url

sub is_url {
    my ($url) = @_;

    return $url =~ /s?https?:\/\/[-_.!~*'()a-zA-Z0-9;\/?:\@&=+\$,%#]+/;
}

sub discover_tb {
    my ( $url, $find_all, $contents ) = @_;
    my $c = '';
    if ($contents) {
        $c = $$contents;
    }
    else {
        my $ua = MT->new_ua;
        ## Wrap this in an eval in case some versions don't support it.
        my $req = HTTP::Request->new( GET => $url );
        eval {
            $ua->timeout(30);    # limit timeout to 30 seconds
            $ua->parse_head(0);
        };

        # prevent downloads of non-text content
        my $res = $ua->request(
            $req,
            sub {
                my ( $data, $res, $po ) = @_;
                die
                  unless $c ne ''
                      or $res->header('Content-Type') =~ m!^text/!;
                $c .= $data;
            },
            16384
        );
        return unless $res->is_success;
    } ## end else [ if ($contents) ]
    ( my $url_no_anchor = $url )           =~ s/#.*$//;
    ( my $url_no_host   = $url_no_anchor ) =~ s!^https?://.*/!!i;
    my (@items);
    while ( $c =~ m!(<rdf:RDF.*?</rdf:RDF>)!sg ) {
        my $rdf = $1;
        my ($perm_url) = $rdf =~ m!dc:identifier="([^"]+)"!;    #"
        $perm_url ||= "";
        ( my $perm_url_no_host = $perm_url ) =~ s!https?://.*/!!i;
        $perm_url_no_host =~ s/#.*$//;
        next
          unless $find_all
              || $perm_url         eq $url
              || $perm_url         eq $url_no_anchor
              || $perm_url_no_host eq $url_no_host;
        ( my $inner = $rdf ) =~ s!^.*?<rdf:Description!!s;
        my $item = { permalink => $perm_url };

        while ( $inner =~ /([\w:]+)="([^"]*)"/gs ) {            #"
            $item->{$1} = $2;
        }
        $item->{ping_url} = $item->{'trackback:ping'};
        next unless $item->{ping_url};
        $item->{title} = decode_xml( $item->{'dc:title'} );
        if ( !$item->{title} && $rdf =~ m!dc:description="([^"]+)"! ) {    #"
            $item->{title} =
              MT::I18N::first_n_text(
                                      $1,
                                      MT::I18N::const(
                                               'LENGTH_ENTRY_TITLE_FROM_TEXT')
              ) . '...';
        }
        push @items, $item;
        last unless $find_all;
    } ## end while ( $c =~ m!(<rdf:RDF.*?</rdf:RDF>)!sg)
    return unless @items;
    $find_all ? \@items : $items[0];
} ## end sub discover_tb

{
    my %Data = (
             'by' => {
                 name     => 'Attribution',
                 requires => [qw( Attribution Notice )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
             },
             'by-nd' => {
                          name     => 'Attribution-NoDerivs',
                          requires => [qw( Attribution Notice )],
                          permits  => [qw( Reproduction Distribution )],
             },
             'by-nd-nc' => {
                             name     => 'Attribution-NoDerivs-NonCommercial',
                             requires => [qw( Attribution Notice )],
                             permits  => [qw( Reproduction Distribution )],
                             prohibits => [qw( CommercialUse)],
             },
             'by-nc' => {
                 name     => 'Attribution-NonCommercial',
                 requires => [qw( Attribution Notice )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
                 prohibits => [qw( CommercialUse )],
             },
             'by-nc-sa' => {
                 name     => 'Attribution-NonCommercial-ShareAlike',
                 requires => [qw( Attribution Notice ShareAlike )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
                 prohibits => [qw( CommercialUse )],
             },
             'by-sa' => {
                 name     => 'Attribution-ShareAlike',
                 requires => [qw( Attribution Notice ShareAlike )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
             },
             'nd' => {
                       name     => 'NonDerivative',
                       requires => [qw( Notice )],
                       permits  => [qw( Reproduction Distribution )],
             },
             'nd-nc' => {
                          name      => 'NonDerivative-NonCommercial',
                          requires  => [qw( Notice )],
                          permits   => [qw( Reproduction Distribution )],
                          prohibits => [qw( CommercialUse )],
             },
             'nc' => {
                 name     => 'NonCommercial',
                 requires => [qw( Notice )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
                 prohibits => [qw( CommercialUse )],
             },
             'nc-sa' => {
                 name     => 'NonCommercial-ShareAlike',
                 requires => [qw( Notice ShareAlike )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
                 prohibits => [qw( CommercialUse )],
             },
             'sa' => {
                 name     => 'ShareAlike',
                 requires => [qw( Notice ShareAlike )],
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
             },
             'pd' => {
                 name    => 'PublicDomain',
                 permits => [qw( Reproduction Distribution DerivativeWorks )],
             },
    );

    sub cc_url {
        my ($code) = @_;
        my $url;
        my ( $real_code, $license_url, $image_url );
        if ( ( $real_code, $license_url, $image_url )
             = $code =~ /(\S+) (\S+) (\S+)/ )
        {
            return $license_url;
        }
        $code eq 'pd'
          ? "http://web.resource.org/cc/PublicDomain"
          : "http://creativecommons.org/licenses/$code/1.0/";
    }

    sub cc_rdf {
        my ($code) = @_;
        my $url    = cc_url($code);
        my $rdf    = <<RDF;
<License rdf:about="$url">
RDF
        for my $type (qw( requires permits prohibits )) {
            for my $item ( @{ $Data{$code}{$type} } ) {
                $rdf .= <<RDF;
<$type rdf:resource="http://web.resource.org/cc/$item" />
RDF
            }
        }
        $rdf . "</License>\n";
    }

    sub cc_name {
        my ($code) = ( $_[0] =~ /(\S+) \S+ \S+/ );
        $code ||= $_[0];
        $Data{$code}{name};
    }

    sub cc_image {
        my ($code) = @_;
        my $url;
        my ( $real_code, $license_url, $image_url );
        if ( ( $real_code, $license_url, $image_url )
             = $code =~ /(\S+) (\S+) (\S+)/ )
        {
            return $image_url;
        }
        "http://creativecommons.org/images/public/"
          . ( $code eq 'pd' ? 'norights' : 'somerights' );
    }
}

sub mark_odd_rows {
    my ($list) = @_;
    my $i = 1;
    for my $row (@$list) {
        $row->{is_odd} = $i++ % 2 == 1;
    }
}

%Languages = (
    'en' => [
        [qw( Sunday Monday Tuesday Wednesday Thursday Friday Saturday )],
        [
           qw( January February March April May June
             July August September October November December )
        ],
        [qw( AM PM )],
    ],

    'fr' => [
              [qw( dimanche lundi mardi mercredi jeudi vendredi samedi )],
              [ (
                    'janvier',   "f&#xe9;vrier",
                    'mars',      'avril',
                    'mai',       'juin',
                    'juillet',   "ao&#xfb;t",
                    'septembre', 'octobre',
                    'novembre',  "d&#xe9;cembre"
                 )
              ],
              [qw( AM PM )],
              "%e %B %Y %kh%M",
              "%e %B %Y",
              "%kh%M",
    ],

    'es' => [ [ (
              'Domingo', 'Lunes',
              'Martes',  "Mi&#xe9;rcoles",
              'Jueves',  'Viernes',
              "S&#xe1;bado"
           )
        ],
        [
           qw( Enero Febrero Marzo Abril Mayo Junio Julio Agosto
             Septiembre Octubre Noviembre Diciembre )
        ],
        [qw( AM PM )],
        "%e de %B %Y a las %I:%M %p",
        "%e de %B %Y",
    ],

    'pt' => [ [ (
                    'domingo',          'segunda-feira',
                    "ter&#xe7;a-feira", 'quarta-feira',
                    'quinta-feira',     'sexta-feira',
                    "s&#xe1;bado"
                 )
              ],
              [ (
                    'janeiro',  'fevereiro', "mar&#xe7;o", 'abril',
                    'maio',     'junho',     'julho',      'agosto',
                    'setembro', 'outubro',   'novembro',   'dezembro'
                 )
              ],
              [qw( AM PM )],
    ],

    'nl' => [ [
           qw( zondag maandag dinsdag woensdag donderdag vrijdag
             zaterdag )
        ],
        [
           qw( januari februari maart april mei juni juli augustus
             september oktober november december )
        ],
        [qw( am pm )],
        "%e %B %Y %k:%M",
        "%e %B %Y",
        "%k:%M",
    ],

    'dk' => [ [ (
              "s&#xf8;ndag", 'mandag', 'tirsdag', 'onsdag',
              'torsdag',     'fredag', "l&#xf8;rdag"
           )
        ],
        [
           qw( januar februar marts april maj juni juli august
             september oktober november december )
        ],
        [qw( am pm )],
        "%d.%m.%Y %H:%M",
        "%d.%m.%Y",
        "%H:%M",
    ],

    'se' => [ [ (
              "s&#xf6;ndag", "m&#xe5;ndag", 'tisdag', 'onsdag',
              'torsdag',     'fredag',      "l&#xf6;rdag"
           )
        ],
        [
           qw( januari februari mars april maj juni juli augusti
             september oktober november december )
        ],
        [qw( FM EM )],
    ],

    'no' => [ [ (
              "S&#xf8;ndag", "Mandag", 'Tirsdag', 'Onsdag',
              'Torsdag',     'Fredag', "L&#xf8;rdag"
           )
        ],
        [
           qw( Januar Februar Mars April Mai Juni Juli August
             September Oktober November Desember )
        ],
        [qw( FM EM )],
    ],

    'de' => [ [
           qw( Sonntag Montag Dienstag Mittwoch Donnerstag Freitag
             Samstag )
        ],
        [ (
              'Januar',    'Februar', "M&#xe4;rz", 'April',
              'Mai',       'Juni',    'Juli',      'August',
              'September', 'Oktober', 'November',  'Dezember'
           )
        ],
        [qw( FM EM )],
        "%e.%m.%y %k:%M",
        "%e.%m.%y",
        "%k:%M",
    ],

    'it' => [ [ (
              'Domenica',     "Luned&#xec;",
              "Marted&#xec;", "Mercoled&#xec;",
              "Gioved&#xec;", "Venerd&#xec;",
              'Sabato'
           )
        ],
        [
           qw( Gennaio Febbraio Marzo Aprile Maggio Giugno Luglio
             Agosto Settembre Ottobre Novembre Dicembre )
        ],
        [qw( AM PM )],
        "%d.%m.%y %H:%M",
        "%d.%m.%y",
        "%H:%M",
    ],

    'pl' => [ [ (
                    'niedziela', "poniedzia&#322;ek",
                    'wtorek',    "&#347;roda",
                    'czwartek',  "pi&#261;tek",
                    'sobota'
                 )
              ],
              [ (
                    'stycznia',      'lutego',
                    'marca',         'kwietnia',
                    'maja',          'czerwca',
                    'lipca',         'sierpnia',
                    "wrze&#347;nia", "pa&#378;dziernika",
                    'listopada',     'grudnia'
                 )
              ],
              [qw( AM PM )],
              "%e %B %Y %k:%M",
              "%e %B %Y",
              "%k:%M",
    ],

    'fi' => [ [
           qw( sunnuntai maanantai tiistai keskiviikko torstai perjantai
             lauantai )
        ],
        [ (
              'tammikuu',      'helmikuu',
              'maaliskuu',     'huhtikuu',
              'toukokuu',      "kes&#xe4;kuu",
              "hein&#xe4;kuu", 'elokuu',
              'syyskuu',       'lokakuu',
              'marraskuu',     'joulukuu'
           )
        ],
        [qw( AM PM )],
        "%d.%m.%y %H:%M",
    ],

    'is' => [ [ (
                    'Sunnudagur',            "M&#xe1;nudagur",
                    "&#xde;ri&#xf0;judagur", "Mi&#xf0;vikudagur",
                    'Fimmtudagur',           "F&#xf6;studagur",
                    'Laugardagur'
                 )
              ],
              [ (
                    "jan&#xfa;ar",    "febr&#xfa;ar",
                    'mars',           "apr&#xed;l",
                    "ma&#xed;",       "j&#xfa;n&#xed;",
                    "j&#xfa;l&#xed;", "&#xe1;g&#xfa;st",
                    'september',      "okt&#xf3;ber",
                    "n&#xf3;vember",  'desember'
                 )
              ],
              [qw( FH EH )],
              "%d.%m.%y %H:%M",
    ],

    'si' => [ [ (
              'nedelja',      'ponedeljek', 'torek', 'sreda',
              "&#xe3;etrtek", 'petek',      'sobota',
           )
        ],
        [
           qw( januar februar marec april maj junij julij avgust
             september oktober november december )
        ],
        [qw( AM PM )],
        "%d.%m.%y %H:%M",
    ],

    'cz' => [ [ (
                    'Ned&#283;le',     'Pond&#283;l&#237;',
                    '&#218;ter&#253;', 'St&#345;eda',
                    '&#268;tvrtek',    'P&#225;tek',
                    'Sobota'
                 )
              ],
              [ (
                    'Leden',               '&#218;nor',
                    'B&#345;ezen',         'Duben',
                    'Kv&#283;ten',         '&#268;erven',
                    '&#268;ervenec',       'Srpen',
                    'Z&#225;&#345;&#237;', '&#216;&#237;jen',
                    'Listopad',            'Prosinec'
                 )
              ],
              [qw( AM PM )],
              "%e. %B %Y %k:%M",
              "%e. %B %Y",
              "%k:%M",
    ],

    'sk' => [ [ (
                    'nede&#318;a',  'pondelok', 'utorok', 'streda',
                    '&#353;tvrtok', 'piatok',   'sobota'
                 )
              ],
              [ (
                    'janu&#225;r', 'febru&#225;r',
                    'marec',       'apr&#237;l',
                    'm&#225;j',    'j&#250;n',
                    'j&#250;l',    'august',
                    'september',   'okt&#243;ber',
                    'november',    'december'
                 )
              ],
              [qw( AM PM )],
              "%e. %B %Y %k:%M",
              "%e. %B %Y",
              "%k:%M",
    ],

    'jp' => [ [
                 '&#26085;&#26332;&#26085;', '&#26376;&#26332;&#26085;',
                 '&#28779;&#26332;&#26085;', '&#27700;&#26332;&#26085;',
                 '&#26408;&#26332;&#26085;', '&#37329;&#26332;&#26085;',
                 '&#22303;&#26332;&#26085;'
              ],
              [qw( 1 2 3 4 5 6 7 8 9 10 11 12 )],
              [qw( AM PM )],
              "%Y&#24180;%b&#26376;%e&#26085; %H:%M",
              "%Y&#24180;%b&#26376;%e&#26085;",
              "%H:%M",
              "%Y&#24180;%b&#26376;",
              "%b&#26376;%e&#26085;",
    ],

    'et' => [ [
           qw( p&uuml;hap&auml;ev esmasp&auml;ev teisip&auml;ev
             kolmap&auml;ev neljap&auml;ev reede laup&auml;ev )
        ],
        [ (
              'jaanuar',   'veebruar', 'm&auml;rts', 'aprill',
              'mai',       'juuni',    'juuli',      'august',
              'september', 'oktoober', 'november',   'detsember'
           )
        ],
        [qw( AM PM )],
        "%m.%d.%y %H:%M",
        "%e. %B %Y",
        "%H:%M",
    ],

    'ru' => [ [ (
                 'Воскресенье', 'Понедельник',
                 'Вторник',         'Среда',
                 'Четверг',         'Пятница',
                 'Суббота'
               )
             ],
             [ (
                 '&#1071;&#1085;&#1074;&#1072;&#1088;&#1100;',
                 '&#1060;&#1077;&#1074;&#1088;&#1072;&#1083;&#1100;',
                 '&#1052;&#1072;&#1088;&#1090;',
                 '&#1040;&#1087;&#1088;&#1077;&#1083;&#1100;',
                 '&#1052;&#1072;&#1081;',
                 '&#1048;&#1102;&#1085;&#1100;',
                 '&#1048;&#1102;&#1083;&#1100;',
                 '&#1040;&#1074;&#1075;&#1091;&#1089;&#1090;',
                 '&#1057;&#1077;&#1085;&#1090;&#1103;&#1073;&#1088;&#1100;',
                 '&#1054;&#1082;&#1090;&#1103;&#1073;&#1088;&#1100;',
                 '&#1053;&#1086;&#1103;&#1073;&#1088;&#1100;',
                 '&#1044;&#1077;&#1082;&#1072;&#1073;&#1088;&#1100;'
               )
             ],
             [qw( AM PM )],
             "%d.%m.%Y %H:%M",
             "%d.%m.%Y",
             "%H:%M",
    ],
);

$Languages{en_US} = $Languages{en_us} = $Languages{"en-us"} = $Languages{en};
$Languages{ja} = $Languages{jp};

sub browser_language {
    my @browser_langs = ( $ENV{HTTP_ACCEPT_LANGUAGE} || '' ) =~ m{ 
        ( 
                [a-z]{2}      # en 
                (?:-[a-z]{2})?  # -us 
        ) 
        \s* 
        (?: 
                ; \s* q\s*=\s*  # ; q= 
                (?:1|0\.[0-9]+)   # 0.xx or 1 
        )? 
    }xmsg;
    my $mt_langs = MT->supported_languages;
    foreach my $lang (@browser_langs) {
        if ( $mt_langs->{$lang} ) {
            return $lang;
        }

        $lang =~ m/(.*)-.*/s;
        if ( $mt_langs->{$1} ) {
            return $1;
        }
    }

    return 'en-us';
} ## end sub browser_language

sub launch_background_tasks {
    return !(    $ENV{MOD_PERL}
              || $ENV{FAST_CGI}
              || !MT->config->LaunchBackgroundTasks );
}

sub start_background_task {
    my ($func) = @_;
    if ( !launch_background_tasks() ) { $func->(); }
    else {
        MT::ObjectDriverFactory->cleanup();
        $| = 1;    # Flush open filehandles
        my $pid = fork();
        if ( !$pid ) {

            # child
            close STDIN;
            open STDIN, "</dev/null";
            close STDOUT;
            open STDOUT, ">/dev/null";
            close STDERR;
            open STDERR, ">/dev/null";

            MT::Object->driver;    # This inititalizes driver
            MT::ObjectDriverFactory->configure();
            $func->();
            CORE::exit(0) if defined($pid) && !$pid;
        }
        else {
            MT::Object->driver;    # This inititalizes driver
            MT::ObjectDriverFactory->configure();
            return 1;
        }
    } ## end else [ if ( !launch_background_tasks...)]
} ## end sub start_background_task

{
    eval { require bytes; 1; };

    sub addbin {
        my ( $a, $b ) = @_;
        my $length = ( length $a > length $b ? length $a : length $b );

        $a = "\0" x ( $length - ( length $a ) ) . $a;
        $b = "\0" x ( $length - ( length $b ) ) . $b;
        my $carry  = 0;
        my $result = '';
        for ( my $i = 1; $i <= $length; $i++ ) {
            my $adigit = ord( substr( $a, -$i, 1 ) );
            my $bdigit = ord( substr( $b, -$i, 1 ) );
            my $rdigit = $adigit + $bdigit + $carry;
            $carry  = $rdigit / 256;
            $result = chr( $rdigit % 256 ) . $result;
        }
        if ($carry) {
            return $result = chr($carry) . $result;
        }
        else {
            return $result;
        }
    } ## end sub addbin

    sub multbindec {
        my ( $a, $b ) = @_;

        # $b is decimal-ascii, $b < 256
        my @result;
        $result[ ( length $a ) ] = 0;
        for ( my $i = 1; $i <= length $a; $i++ ) {
            my $adigit = substr( $a, -$i, 1 );
            $result[ -$i ] = ord($adigit) * $b;
        }

        for ( my $i = 2; $i <= scalar @result; $i++ ) {
            $result[ -$i ] += int( $result[ -$i + 1 ] / 256 );
            $result[ -$i + 1 ] = $result[ -$i + 1 ] % 256;
        }

        shift @result while ( @result && ( $result[0] == 0 ) );

        pack( 'C*', @result );
    } ## end sub multbindec

    sub divbindec {
        my ( $a, $b ) = @_;

        # $b is decimal-ascii, $b < 256

        my $acc = ord( substr( $a, 0, 1 ) );
        my $quot;
        while ( length $a ) {
            $a = substr( $a, 1 );
            $quot .= chr( $acc / $b );
            $acc = $acc % $b;
            if ( length $a ) {
                $acc = $acc * 256 + ord( substr( $a, 0, 1 ) );
            }
        }
        return ( $quot, $acc );
    }

    sub dec2bin {
        my ($decimal) = @_;
        my @digits = split //, $decimal;
        my $result = "";
        foreach my $d (@digits) {
            $result = multbindec( $result, 10 );
            $result = addbin( pack( 'c', $d ), $result );
        }
        while ( substr( $result, 0, 1 ) eq "\0" ) {
            $result = substr( $result, 1 );
        }
        $result;
    }

    sub bin2dec {
        my $bin    = $_[0];
        my $result = '';
        my $rem    = 0;
        while ( ( length $bin ) && ( $bin ne "\0" ) ) {
            ( $bin, $rem ) = divbindec( $bin, 10 );
            $result = $rem . $result;
            $bin = substr( $bin, 1 ) if ( substr( $bin, 0, 1 ) eq "\0" );
        }
        $result;
    }


    sub perl_sha1_digest
    {    # thanks to Adam Back for the starting point of this
        my ($message) = @_;
        my $init_string
          = 'D9T4C`>_-JXF8NMS^$#)4=L/2X?!:@GF9;MGKH8\;O-S*8L\'6';

        # 67452301 efcdab89 98badcfe 10325476 c3d2e1f0
        my @A = unpack "N*", unpack 'u', $init_string;
        my @K = splice @A, 5, 4;
        sub M { my ( $x, $m ); ( $x = pop ) - ( $m = 1 + ~0 ) * int $x / $m }; # modulo 0x100000000

        sub L {
            my ( $n, $x );
            $n = pop;
            ( ( $x = pop ) << $n | 2**$n - 1 & $x >> 32 - $n ) & (0xffffffff);
        }    # left-rotate bit vector
             # magic SHA1 functions
        my @F = (
            sub { my ( $a, $b, $c, $d ) = @_; $b & ( $c ^ $d ) ^ $d },
            sub { my ( $a, $b, $c, $d ) = @_; $b ^ $c ^ $d },
            sub {
                my ( $a, $b, $c, $d ) = @_;
                ( $b | $c ) & $d | $b & $c;
            },
            sub { my ( $a, $b, $c, $d ) = @_; $b ^ $c ^ $d }
        );
        my $F = sub {
            my $which = shift;
            my ( $a, $b, $c, $d ) = @_;
            if ( $which == 0 ) { $b & ( $c ^ $d ) ^ $d }
            elsif ( $which == 1 ) { $b ^ $c ^ $d }
            elsif ( $which == 2 ) { ( $b | $c ) & $d | $b & $c }
            elsif ( $which == 3 ) { $b ^ $c ^ $d }
        };

        my ( $l, $r, $p, $t, $S, @W, $P );
        do {
            $P = substr( $message, 0, 64 );
            $message = length $message >= 64 ? substr( $message, 64 ) : "";
            $l += $r = length $P;
            $r++, $P .= "\x80" if $r < 64 && !$p++;
            @W = unpack 'N16', $P . "\0" x ( 64 - length($P) );
            $W[15] = $l * 8 if $r < 57;
            for ( 16 .. 79 ) {
                push @W,
                  L(
                     $W[ $_ - 3 ] ^ $W[ $_ - 8 ] ^ $W[ $_ - 14 ]
                       ^ $W[ $_ - 16 ],
                     1
                  );
            }
            my ( $a, $b, $c, $d, $e ) = @A;
            for ( 0 .. 79 ) {
                $t = M(
                          ( $F->( int( $_ / 20 ), $a, $b, $c, $d ) ) 
                        + $e 
                          + $W[$_]
                          + $K[ $_ / 20 ]
                          + L $a,
                        5
                );
                $e = $d;
                $d = $c;
                $c = L( $b, 30 );
                $b = $a;
                $a = $t;
            }
            $A[0] = M( $A[0] + $a );
            $A[1] = M( $A[1] + $b );
            $A[2] = M( $A[2] + $c );
            $A[3] = M( $A[3] + $d );
            $A[4] = M( $A[4] + $e );
        } while $r > 56;

        pack( 'N*', @A[ 0 .. 4 ] );
    } ## end sub perl_sha1_digest
}

sub perl_sha1_digest_hex {
    sprintf( "%.8x" x 5, unpack( 'N*', &perl_sha1_digest(@_) ) );
}

sub perl_sha1_digest_base64 {
    require MIME::Base64;
    MIME::Base64::encode_base64( perl_sha1_digest(@_), '' );
}

{
    my $has_crypt_dsa;

    sub dsa_verify {
        my %param = @_;

        unless ( defined $has_crypt_dsa ) {
            eval { require Crypt::DSA; };
            $has_crypt_dsa = $@ ? 0 : 1;
        }
        if ( $has_crypt_dsa && !$param{ForcePerl} ) {
            $param{Key} = bless $param{Key}, 'Crypt::DSA::Key';
            $param{Signature} = bless $param{Signature},
              'Crypt::DSA::Signature';
            return Crypt::DSA->new->verify(%param);
        }
        else {
            require Math::BigInt;

            my ( $key, $dgst, $sig );

            Carp::croak __PACKAGE__ . "dsa_verify: Need a Key"
              unless $key = $param{Key};

            unless ( $dgst = $param{Digest} ) {
                Carp::croak "dsa_verify: Need either Message or Digest"
                  unless $param{Message};
                $dgst = perl_sha1_digest( $param{Message} );
            }
            Carp::croak "dsa_verify: Need a Signature"
              unless $sig = $param{Signature};
            my $r       = new Math::BigInt( $sig->{r} );
            my $s       = new Math::BigInt( $sig->{'s'} );
            my $p       = new Math::BigInt( $key->{p} );
            my $q       = new Math::BigInt( $key->{'q'} );
            my $g       = new Math::BigInt( $key->{g} );
            my $pub_key = new Math::BigInt( $key->{pub_key} );
            my $u2      = $s->bmodinv($q);

            my $u1 = new Math::BigInt( "0x" . unpack( "H*", $dgst ) );

            $u1 = $u1->bmul($u2)->bmod($q);
            $u2 = $r->bmul($u2)->bmod($q);
            my $t1 = $g->bmodpow( $u1, $p );
            my $t2 = $pub_key->bmodpow( $u2, $p );
            $u1 = $t1->bmul($t2)->bmod( $key->{p} );
            $u1 = $u1->bmod( $key->{'q'} );
            my $result = $u1->bcmp( $sig->{r} );
            return defined($result) ? $result == 0 : 0;
        } ## end else [ if ( $has_crypt_dsa &&...)]
    } ## end sub dsa_verify
}

# TBD: fill in the contracts of these.
sub sanitize_input {
    my $str = shift;

    # Convert decimal entities (&#112; => p)
    $str =~ s/&#(\d{1,3});/chr($1)/eg;

    # Convert hex entities (&#x70; => p)
    $str =~ s/&#x(\d{2});/chr(hex($1))/eg;

    # Convert URL encodings (%70 => p)
    $str =~ s/\%([0-9A-Z]{2})/chr(hex($1))/eig;

# Remove any HTML comments in the form of <! ... >
    $str =~ s/\x3c\!.+?\x3e//g;

# Remove any #'s since we will be using it as a delimiter
# This is safe since it isn't something that would
# be included in a blacklist.
    $str =~ tr/#//d;

    return $str;
} ## end sub sanitize_input

sub extract_domain {
    my $str = shift;
    $str =~ s#^(.*?)/.*$#$1#;
    lc($str);
}

sub extract_urls {
    my @strings = @_;
    my ( %domain, @urls );
    foreach (@strings) {
        next unless ( $_ and $_ ne '' );
        local $_ = sanitize_input($_);
        while (m#(?:https?:)?//(?:www.)?([^\s'"<>]+)#gi) {
            my $u = $1;
            $u =~ s#/$##;
            next if $domain{$u};
            $domain{$u} = extract_domain($u);
        }
    }
    return (%domain);
}

sub extract_domains {
    my %u = extract_urls(@_);
    values %u;
}

sub escape_unicode {
    my $text = shift;
    $text =~ s/((?:[\xc2-\xdf][\x80-\xbf])|
                (?:(?:(?:\xe0[\xa0-\xbf])|
                      (?:[\xe1-\xec][\x80-\xbf])|
                      (?:\xed[\x80-\x9f])|
                      (?:[\xee-\xef][\x80-\xbf]))[\x80-\xbf])|
                (?:(?:\xf0[\x90-\xbf])|
                   (?:[\xf1-\xf3][\x80-\xbf])|
                   (?:\xf4[\x80-\x8f])[\x80-\xbf]{2}))/
                '&#'.hex(unpack("H*", MT::I18N::encode_text($1, 'utf-8', 'ucs2'))).';'
            /egx;
    $text;
}

sub unescape_unicode {
    my $text = shift;
    $text =~ s/\&\#(\d+);/pack("H*", sprintf("%X",$1))/egx;
    $text = MT::I18N::encode_text( $text, 'ucs2', undef );
}

{
    my $initialized_sax;

    sub init_sax {
        require XML::SAX;
        if ( @{ XML::SAX->parsers } == 1 ) {
            map {
                eval { XML::SAX->add_parser($_) }
              } qw( XML::SAX::Expat XML::LibXML::SAX::Parser
              XML::LibXML::SAX
              XML::SAX::ExpatXS );
        }
        $initialized_sax = 1;
    }

    sub sax_parser {
        init_sax() unless $initialized_sax;
        require XML::SAX::ParserFactory;
        my $f = XML::SAX::ParserFactory->new;
        $f->parser();
    }
}

sub multi_iter {
    my ( $iters, $picker ) = @_;
    my @streams;
    foreach my $iter (@$iters) {
        my $head = $iter->();
        push @streams, { iter => $iter, head => $head };
    }
    my $finish = sub {
        foreach my $iter (@streams) {
            $iter->{iter}->end;
        }
    };
    my $iter = sub {
        my ($f) = @_;

        # find the head with greatest created_on
        my $which;
        foreach my $iter (@streams) {
            next unless defined( $iter->{head} );
            if ( !$which ) {
                $which = $iter;
                last unless $picker;
            }
            else {
                if ( !$picker
                     || (    $picker
                          && $picker->( $iter->{head}, $which->{head} ) ) )
                {
                    $which = $iter;
                }
            }
        }
        return unless $which;

        # Advance the chosen one
        my $result = $which->{head};
        if ( defined $result ) {
            $which->{head} = $which->{iter}->();
        }
        $result;
    };
    return Data::ObjectDriver::Iterator->new( $iter, $finish );
} ## end sub multi_iter

sub trim {
    my $string = shift;
    return unless defined $string;
    $string =~ s/^\s+|\s+$//gs;
    $string;
}

sub ltrim {
    my $string = shift;
    return unless defined $string;
    $string =~ s/^\s+//s;
    $string;
}

sub rtrim {
    my $string = shift;
    return unless defined $string;
    $string =~ s/\s+$//s;
    $string;
}

sub asset_cleanup {
    my ($str) = @_;
    $str =~ s/
        <(?:[Ff][Oo][Rr][Mm]|[Ss][Pp][Aa][Nn])
        ([^>]*?)
        \s
        mt:asset-id="\d+"
        ([^>]*?>)(.*?)
        <\/(?:[Ff][Oo][Rr][Mm]|[Ss][Pp][Aa][Nn])>
    /
    my $attr = $1 . $2;
    my $inner = $3;
    $attr =~ s!\s[Cc][Oo][Nn][Tt][Ee][Nn][Tt][Ee][Dd][Ii][Tt][Aa][Bb][Ll][Ee]=(['"][^'"]*?['"]|[Ff][Aa][Ll][Ss][Ee])!!;
    '<span' . $attr . $inner . '<\/span>'
    /gsex;
    return $str;
}

sub caturl {
    return '' unless @_;

    my $url = shift;
    foreach (@_) {
        my $u = $_;
        next unless $u;
        $u =~ s!^/!!;
        $url .= '/' unless $url =~ m!/$!;
        $url .= $u;
    }
    return $url;
}

sub get_newsbox_html {
    my ( $newsbox_url, $kind, $cached_only ) = @_;

    return unless $newsbox_url;
    return unless is_url($newsbox_url);
    return unless $kind && ( length($kind) == 2 );
    $cached_only ||= 0;

    my $NEWSCACHE_TIMEOUT = 60 * 60 * 24;
    my $sess_class        = MT->model('session');
    my ($news_object)     = ("");
    my $retries           = 0;
    $news_object = $sess_class->load( { id => $kind } );
    my $refresh_news;
    if ( $news_object
         && ( $news_object->start() < ( time - $NEWSCACHE_TIMEOUT ) ) )
    {
        $refresh_news = 1;
    }
    my $last_available_news
      = MT::I18N::encode_text( $news_object->data(), 'utf-8', undef )
      if $news_object;
    return $last_available_news unless $refresh_news || !$news_object;
    return q() if $cached_only;

    # don't block the dashboard for more than 10 seconds to fetch
    # the news feed...
    my $ua = MT->new_ua( { timeout => 10 } );
    return $last_available_news unless $ua;

    my $req    = new HTTP::Request( GET => $newsbox_url );
    my $resp   = $ua->request($req);
    my $result = $resp->content();
    if ( !$resp->is_success() || !$result ) {

        # failure; either timeout or worse
        # if news_object is available, bump up it's expiration
        # so we don't attempt to hit the server again
        # for an hour
        if ( !$news_object ) {
            $news_object = MT::Session->new;
            $news_object->set_values(
                                 { id => $kind, kind => $kind, data => '' } );
            $last_available_news = '';
            $refresh_news        = 1;
        }
        if ( defined($last_available_news) && $refresh_news ) {
            $news_object->start( ( time - $NEWSCACHE_TIMEOUT ) + 60 * 60 );
            $news_object->save;
        }
        return $last_available_news;
    }
    require MT::Sanitize;

    # allowed html
    my $spec = 'a href,* style class id,ul,li,div,span,br';
    $result = MT::Sanitize->sanitize( $result, $spec );
    $news_object = MT::Session->new();
    $news_object->set_values(
           { id => $kind, kind => $kind, start => time(), data => $result } );
    $news_object->save();
    $result = MT::I18N::encode_text( $result, 'utf-8', undef );
    return $result;
} ## end sub get_newsbox_html

sub sanitize_embed {
    my ( $str, $opt ) = @_;

    $opt ||= {};
    my $eh   = $opt->{error_handler};
    my $blog = $opt->{blog};

    # Check for valid domains...

    my @domains = extract_domains($str);

    my @whitelist = map { lc $_ } split /\s+/s,
      ( MT->config('EmbedDomainWhitelist') || '' );

    my $re = '';
    foreach my $d (@whitelist) {
        $re .= '|' unless $re eq '';
        $re .= '(?:\A|\.)' . quotemeta($d);
    }
    $re = qr/($re)$/;

    foreach my $d (@domains) {
        unless ( $d =~ m/$re/ ) {
            my $err = MT->translate( "Invalid domain: '[_1]'", $d );
            return $eh->error($err) if $err;
            die $err;
        }
    }


    # Sanitize embed content

    require MT::Sanitize;

    my $gspec = ( $blog ? $blog->sanitize_spec : undef )
      || MT->config('GlobalSanitizeSpec');

    my $spec = $gspec
      . ',embed * !style,object id classid width height,param/ name value,script src type,div';
    my $sanitized = MT::Sanitize->sanitize( $str, $spec );

    # Don't permit any actual script inside a script tag (external
    # script loads are okay for the sake of an embed, as long as the
    # domain is permitted), but arbitrary script code is not okay.
    $sanitized =~ s!(<script[^>]*>)(?:.+?)(</script>)!$1$2!igs;

    return $sanitized;
} ## end sub sanitize_embed

sub log_time {
    return
      format_ts( '[%Y-%m-%d %H:%M:%S]',
                 epoch2ts( undef, time ),
                 undef, MT->config->DefaultLanguage, 0 );
}

## FIXME
# This method is to supplement CGI.pm's lack of read method.
# Some XML parsers (XML::SAX::ExpatXS and XML::LibXML to name a few)
# requires OO access to filehandles.
# Once CGI solved this issue, this method will be removed.
*Fh::read = sub {
    read( $_[0], $_[1], $_[2], $_[3] || 0 );
};

sub make_string_csv {
    my ( $value, $enc ) = @_;
    $value =~ s/\r|\r\n/\n/gs;
    if ( (
              ( index( $value, '"' ) > -1 )
           || ( index( $value, '\n' ) > -1 )
           || ( index( $value, ',' ) > -1 )
         )
         && !( $value =~ m/^".*"$/gs )
      )
    {
        $value = "\"$value\"";
    }
    return MT::I18N::encode_text( $value, undef, $enc );
}

sub convert_word_chars {
    my ( $s, $smart_replace ) = @_;

    return '' unless $s;
    return $s if $smart_replace == 2;

    if ($smart_replace) {

        # html character entity replacements
        $s =~ s/\342\200\231/&#8217;/g;
        $s =~ s/\342\200\230/&#8216;/g;
        $s =~ s/\342\200\246/&#133;/g;
        $s =~ s/\342\200\223/-/g;
        $s =~ s/\342\200\224/&#8212;/g;
        $s =~ s/\342\200\234/&#8220;/g;
        $s =~ s/\342\200\235/&#8221;/g;
    }
    else {

        # ascii equivalent replacements
        $s =~ s/\342\200[\230\231]/'/g;
        $s =~ s/\342\200\246/.../g;
        $s =~ s/\342\200\223/-/g;
        $s =~ s/\342\200\224/--/g;
        $s =~ s/\342\200[\234\235]/"/g;
    }

    # While we're fixing Word, remove processing instructions with
    # colons, as they can break PHP.
    $s =~ s{ <\? xml:namespace [^>]*> }{}ximsg;

    return $s;
} ## end sub convert_word_chars

sub translate_naughty_words {
    my ($entry) = @_;

    my $app = MT->instance;
    return if 'utf-8' ne lc( $app->charset );

    my $blog = $entry->blog;

    my $fields = $blog->smart_replace_fields;
    return unless $fields;

    my $smart_replace
      = $blog ? $blog->smart_replace : $app->config->NwcSmartReplace;
    return if $smart_replace == 2;

    my @fields = split( /\s*,\s*/, $fields || '' );
    foreach my $field (@fields) {
        if ( $entry->has_column($field) ) {
            $entry->column(
                            $field,
                            convert_word_chars(
                                                $entry->column($field),
                                                $smart_replace
                            )
            );
        }
        elsif ( $field eq 'tags' ) {
            my @tags
              = map { convert_word_chars( $_, $smart_replace ) } $entry->tags;
            $entry->set_tags(@tags);
        }
    }
} ## end sub translate_naughty_words

sub _pre_to_json {
    my ($ref) = @_;
    if ( 'ARRAY' eq ref($ref) ) {
        my @tmp;
        foreach (@$ref) {
            next unless defined $_;
            if ( ref($_) ) {
                push @tmp, _pre_to_json($_);
            }
            else {

                # Do not decode numeric values because
                # they may be used as a boolean value in JavaScript.
                if ( $_ !~ /^\d+$/ ) {
                    push @tmp,
                      MT::I18N::decode( MT->config->PublishCharset, $_ );
                }
                else {
                    push @tmp, 0 + $_;
                }
            }
        }
        return \@tmp;
    } ## end if ( 'ARRAY' eq ref($ref...))
    elsif ( 'HASH' eq ref($ref) ) {
        my %tmp;
        while ( my ( $k, $v ) = each %$ref ) {
            next unless defined $v;
            if ( ref($v) ) {
                $tmp{$k} = _pre_to_json($v);
            }
            else {

                # Do not decode numeric values because
                # they may be used as a boolean value in JavaScript.
                if ( $v !~ /^\d+$/ ) {
                    $tmp{$k}
                      = MT::I18N::decode( MT->config->PublishCharset, $v );
                }
                else {
                    $tmp{$k} = 0 + $v;
                }
            }
        }
        return \%tmp;
    } ## end elsif ( 'HASH' eq ref($ref...))
    elsif ( 'SCALAR' eq ref($ref) ) {

        # Do not decode numeric values because
        # they may be used as a boolean value in JavaScript.
        my $tmp;
        if ( $$ref !~ /^\d+$/ ) {
            $tmp = MT::I18N::decode( MT->config->PublishCharset, $$ref );
        }
        else {
            $tmp = 0 + $$ref;
        }
        return \$tmp;
    }
    return $ref;
} ## end sub _pre_to_json

sub to_json {
    my ( $orig_val, $args ) = @_;
    require MT::I18N;
    my $value = _pre_to_json($orig_val);
    require JSON;
    my $js = JSON::to_json( $value, $args );
    return MT::I18N::encode( MT->config->PublishCharset, $js );
}

sub deep_do {
    my ( $data, $sub ) = @_;
    if ( ref $data eq 'HASH' ) {
        deep_do( \$_, $sub ) for values %$data;
    }
    elsif ( ref $data eq 'ARRAY' ) {
        deep_do( \$_, $sub ) for @$data;
    }
    elsif ( ref $data eq 'REF' ) {
        deep_do( $$data, $sub );
    }
    elsif ( ref $data eq 'SCALAR' ) {
        $sub->($data);
    }
    elsif ( !ref $data ) {
        $sub->( \$data );
    }
}

sub deep_copy {
    my ( $limit, $depth ) = @_[ 1, 2 ];
    $depth ||= 0;
    if ( defined($limit) && $depth >= $limit ) {
        return $_[0];
    }

    my $ref = ref $_[0];
    if ( !$ref ) {
        $_[0];
    }
    elsif ( $ref eq 'HASH' ) {
        my $hash = $_[0];
        +{
            map( ( $_ => deep_copy( $hash->{$_}, $limit, $depth + 1 ) ),
                keys(%$hash) )
        };
    }
    elsif ( $ref eq 'ARRAY' ) {
        [ map( deep_copy( $_, $limit, $depth + 1 ), @{ $_[0] } ) ];
    }
    elsif ( $ref eq 'SCALAR' ) {
        \${ $_[0] };
    }
    else {
        $_[0];
    }
}

1;

__END__

=head1 NAME

MT::Util - Movable Type utility functions

=head1 SYNOPSIS

    use MT::Util qw( functions );

=head1 DESCRIPTION

I<MT::Util> provides a variety of utility functions used by the Movable Type
libraries.

=head1 USAGE

=head2 start_end_day($ts)

Given I<$ts>, a timestamp in form C<YYYYMMDDHHMMSS>, calculates the timestamp
corresponding to the start of the same day, and, if called in list context,
the end of the day. If called in scalar context, returns one timestamp
corresponding to the start of the day; if called in list context, returns two
timestamps, for the start and end of the day.

For example, given C<20020410160406>, returns C<20020410000000> in scalar
context, and C<20020410000000> and C<20020410235959> in list context.

=head2 start_end_week($ts)

Given I<$ts>, a timestamp in form C<YYYYMMDDHHMMSS>, calculates the timestamp
corresponding to the start of the week, and, if called in list context, the
end of the week. If called in scalar context, returns one timestamp
corresponding to the start of the week; if called in list context, returns two
timestamps, for the start and end of the week.

A week is defined as starting on Sunday.

For example, given C<20020410160406>, returns C<20020407000000> in scalar
context, and C<20020407000000> and C<20020413235959> in list context.

=head2 start_end_month($ts)

Given I<$ts>, a timestamp in form C<YYYYMMDDHHMMSS>, calculates the timestamp
corresponding to the start of the month, and, if called in list context,
the end of the month. If called in scalar context, returns one timestamp
corresponding to the start of the month; if called in list context, returns two
timestamps, for the start and end of the month.

For example, given C<20020410160406>, returns C<20020401000000> in scalar
context, and C<20020401000000> and C<20020430235959> in list context.

=head2 offset_time_list($unix_ts, $blog [, $direction ])

Given I<$unix_ts>, a timestamp in Unix epoch format (seconds since 1970),
applies the timezone offset specified in the blog I<$blog> (either an
I<MT::Blog> object or a numeric blog ID). If daylight saving time is in
effect in the local time zone (determined using the return value from
I<localtime()>), the offset is automatically adjusted.

Returns the return value of I<gmtime()> given the adjusted Unix timestamp.

=head2 format_ts($format, $ts, $blog)

Given a timestamp I<$ts> in form C<YYYYMMDDHHMMSS>, applies the format
specified in I<$format> and returns the formatted string.

If specified, I<$blog> should be an I<MT::Blog> object, from which the
date/time formatting language preference is taken (e.g. English, French, etc.).
If unspecified, English formatting is used.

If I<$format> is C<undef>, and I<$blog> is specified, I<format_ts> will
use a language-specific default format; if a language-specific format is not
defined, or if I<$blog> is unspecified, the default format used is
C<%B %e, %Y %I:%M %p>.

=head2 days_in($month, $year)

Returns the number of days in the month I<$month> in the year I<$year>.
I<$month> should be numeric, starting at C<1> for C<January>. I<$year> should
be a 4-digit year. The number of days is automatically adjusted in a leap
year.

=head2 wday_from_ts($year, $month, $day)

Returns the numeric day of the week, in the range C<0>-C<6>, where C<0> is
C<Sunday>, for the date specified in I<$year>, I<$month>, and I<$day>.
I<$year> should be a 4-digit year; I<$month> a numeric value in the range
C<1>-C<12>; and I<$day> the numeric day of the month.

=head2 first_n_words($str, $n)

Given a string I<$str>, returns the first I<$n> words in the string, after
removing any HTML tags.

=head2 dirify($str)

Munges a string I<$str> so that it is suitable for use as a file/directory
name. HTML is removed; HTML-entities are removed; non-word/space characters
are removed; spaces are changed to underscores; the entire string is
converted to lower-case.

For example, the string C<Foo E<lt>bE<gt>BarE<lt>/bE<gt> E<amp>quot;BazE<amp>quot;> would be transformed into C<foo_bar_baz>.

=head2 encode_html($str)

Encodes any special characters in I<$str> into HTML entities and returns the
transformed string.

If I<HTML::Entities> is available, and if the configuration setting
I<NoHTMLEntities> is not set, uses I<HTML::Entities> for entity-encoding.
Otherwise, very simple encoding is done to catch the most common characters
that need encoding.

=head2 decode_html($str)

Decodes any HTML entities in I<$str> into the corresponding characters and
returns the transformed string.

If I<HTML::Entities> is available, and if the configuration setting
I<NoHTMLEntities> is not set, uses I<HTML::Entities> for entity-decoding.
Otherwise, very simple decoding is done to catch the most common entities
that need decoding.

=head2 remove_html($str)

Removes any HTML tags from I<$str> and returns the result.

=head2 encode_js($str)

Escapes/encodes any special characters in I<$str> so that the string can be
used safely as the value in Javascript; returns the transformed string.

=head2 encode_json($str)

Escapes/encodes any special characters in I<$str> so that the string can be
used safely as the value in JSON, or Javascript Object Notation. User should
note that the requirements for encoding javascript and json are different, 
and thus must be handled differently and separately. This is especially
important when using more modern javascript toolkits like jQuery 1.4; returns 
the transformed string.

=head2 encode_php($str [, $type ])

Escapes/encodes any special characters in I<$str> so that the string can be
used safely as the value in PHP code; returns the transformed string.

I<$type> can be either C<qq> (double-quote interpolation), C<here> (heredoc
interpolation), or C<q> (single-quote interpolation). C<q> is the default.

=head2 spam_protect($email_address)

Given an email address I<$email_address>, encodes any characters that will
identify it as an email address (C<:>, C<@>, and C<.>) into HTML entities,
so that spam harvesters will not see the email address as easily. Returns
the transformed address.

=head2 is_valid_email($email_address)

Checks the email address I<$email_address> for syntax validity; if the
address--or part of it--is valid, I<is_valid_email> returns the valid (part
of) the email address. Otherwise, it returns C<0>.

=head2 perl_sha1_digest($msg)

Returns a SHA1 digest of $msg. The result is the usual packed binary
representation. Use perl_sha1_digest_hex to get a printable string.

=head2 perl_sha1_digest_hex($msg)

Returns a SHA1 digest of $msg. The result is an ASCII string of hex
digits. Use perl_sha1_digest to get a binary representation.

=head2 dsa_verify(Key => $key, Signature => $sig,
    [ Message => $msg | $Digest => $dgst ])

Verifies that sig is a DSA signature of $msg (or $dgst) produced using
the private half of the public key given in $key. Requires
Math::BigInt but doesn't call for any non-perl libraries.

=head2 get_newsbox_html($newsbox_url, $kind)

Retrieves newsbox content from the specified URL.  Content retrieved is
cached in MT::Session for 24 hours under the key specified in I<$kind>.
Content will be sanitized based on pre-defined rules.

=head2 log_time

Returns the current server time in log specific format.

=head2 to_json($reference)

Wrapper method to JSON::to_json which decodes any string value
in I<reference> to UTF-8 strings as JSON::to_json requires.
It then encodes back to the charset specified in PublishCharset
for MT to render json strings properly.

=head2 make_basename($entry)

Method used to derive a basename from an entry's title and optionally its
text content. If you want a basename that is guaranteed to be unique across
all entries in the blog, use make_unique_basename().

=head2 make_unique_basename($entry)

The easiest (read: laziest and normally good enough) way to ensure that
an entry does not get overwritten by another entry with the same title
in an archive that uses the entry basename as the main differentiator is
to make each basename unique across the entire blog.

This method checks for the existence of another entry in the same blog with
the same the basename produced by make_basename() and appends/increments
a counter until a unique basename is derived. (e.g. title, title-1, title-2)

=head2 trim($str)

Trims all leading (ltrim) and trailing (rtrim) whitespace from the input.
For further detail, see the documentation for ltrim and rtrim.
                
=head2 ltrim($str)

Trims all leading whitespace from a string. This includes all space-like
characters (tab, newline, etc) found at the very start of the string and
continuing up to the first non-space character.  Does not remove spaces
following newlines which appear after the first non-spaace character (i.e.
inner-string spaces).

=head2 rtrim($str)

Trims all trailing whitespace from a string. This includes all space-like
characters (tab, newline, etc) found after the very last non-string character
and continuing to the end of the string. Does not remove spaces
before newlines which appear before the last non-spaace character (i.e.
inner-string spaces).

=head2 deep_copy($value, $limit)

Returns the value recursively copied from I<value>.
If I<limit> is specified, this subroutine is not recursively copied from it.

=head2 addbin

=head2 archive_file_for

=head2 asset_cleanup

=head2 bin2dec

=head2 browser_language

=head2 caturl

=head2 cc_image

=head2 cc_name

=head2 cc_rdf

=head2 cc_url

=head2 convert_high_ascii

=head2 convert_word_chars

=head2 dec2bin

=head2 decode_url

=head2 decode_xml

=head2 discover_tb

=head2 divbindec

=head2 encode_phphere

=head2 encode_url

=head2 encode_xml

=head2 epoch2ts

=head2 escape_unicode

=head2 extract_domain

=head2 extract_domains

=head2 extract_urls

=head2 get_entry

=head2 html_text_transform

=head2 init_sax

=head2 is_leap_year

=head2 is_url

=head2 is_valid_date

=head2 is_valid_url

=head2 iso2ts

=head2 iso_dirify

=head2 launch_background_tasks

=head2 leap_day

=head2 leap_year

=head2 make_string_csv

=head2 make_unique_author_basename

=head2 make_unique_category_basename

=head2 mark_odd_rows

=head2 multbindec

=head2 multi_iter

=head2 munge_comment

=head2 offset_time

=head2 perl_sha1_digest_base64

=head2 relative_date

=head2 rich_text_transform

=head2 sanitize_embed

=head2 sanitize_input

=head2 sax_parser

=head2 start_background_task

=head2 start_end_period

=head2 start_end_year

=head2 strip_index

=head2 substr_wref

=head2 translate_naughty_words

=head2 ts2epoch

=head2 ts2iso

=head2 unescape_unicode

=head2 utf8_dirify

=head2 weaken

=head2 week2ymd

=head2 xliterate_utf8

=head2 yday_from_ts

=head1 AUTHOR & COPYRIGHTS

Please see the I<MT> manpage for author, copyright, and license information.

=cut
