package AssetAppearsIn::CMS;
use strict;

use MT::Util qw( format_ts relative_date );

sub list_asset {
    my ($cb, $app, $terms, $args, $param, $hasher) = @_;

    my $default_thumb_width = 75;
    my $default_thumb_height = 75;
    my $default_preview_width = 75;
    my $default_preview_height = 75;

    my $site_path = $app->blog->site_path;

    require File::Basename;
    require JSON;
    my %blogs;
    $$hasher = sub {
        my ( $obj, $row, %param ) = @_;
        my ($thumb_width, $thumb_height) = @param{qw( ThumbWidth ThumbHeight )};
        $row->{id} = $obj->id;
        my $blog = $blogs{ $obj->blog_id } ||= $obj->blog;
        $row->{blog_name} = $blog ? $blog->name : '-';
        $row->{url} = $obj->url; # this has to be called to calculate
        $row->{asset_type} = $obj->class_type;
        $row->{asset_class_label} = $obj->class_label;
        my $file_path = $obj->file_path; # has to be called to calculate
        my $meta = $obj->metadata;
        require MT::FileMgr;
        my $fmgr = MT::FileMgr->new('Local');
        ## TBD: Make sure $file_path is file, not directory.
        if ( $file_path && $fmgr->exists( $file_path ) ) {
            $row->{file_path} = $file_path;
            $row->{file_name} = File::Basename::basename( $file_path );
            my $size = $fmgr->file_size( $file_path );
            $row->{file_size} = $size;
            if ( $size < 1024 ) {
                $row->{file_size_formatted} = sprintf( "%d Bytes", $size );
            }
            elsif ( $size < 1024000 ) {
                $row->{file_size_formatted} =
                  sprintf( "%.1f KB", $size / 1024 );
            }
            else {
                $row->{file_size_formatted} =
                  sprintf( "%.1f MB", $size / 1024000 );
            }
            $meta->{'file_size'} = $row->{file_size_formatted};
        }
        else {
            $row->{file_is_missing} = 1 if $file_path;
        }
        $row->{file_label} = $row->{label} = $obj->label || $row->{file_name} || $app->translate('Untitled');

        if ($obj->has_thumbnail) { 
            $row->{has_thumbnail} = 1;
            my $height = $thumb_height || $default_thumb_height || 75;
            my $width  = $thumb_width  || $default_thumb_width  || 75;
            my $square = $height == 75 && $width == 75;
            @$meta{qw( thumbnail_url thumbnail_width thumbnail_height )}
              = $obj->thumbnail_url( Height => $height, Width => $width , Square => $square );

            $meta->{thumbnail_width_offset}  = int(($width  - $meta->{thumbnail_width})  / 2);
            $meta->{thumbnail_height_offset} = int(($height - $meta->{thumbnail_height}) / 2);

            if ($default_preview_width && $default_preview_height) {
                @$meta{qw( preview_url preview_width preview_height )}
                  = $obj->thumbnail_url(
                    Height => $default_preview_height,
                    Width  => $default_preview_width,
                );
                $meta->{preview_width_offset}  = int(($default_preview_width  - $meta->{preview_width})  / 2);
                $meta->{preview_height_offset} = int(($default_preview_height - $meta->{preview_height}) / 2);
            }
        }
        else {
            $row->{has_thumbnail} = 0;
        }

### New >
        my @appears_in;
        my $place_class = $app->model('objectasset');
        my $place_iter = $place_class->load_iter(
            {
                blog_id => $obj->blog_id || 0,
                asset_id => $obj->parent ? $obj->parent : $obj->id
            }
        );
        while (my $place = $place_iter->()) {
            my $entry_class = $app->model($place->object_ds) or next;
            next unless $entry_class->isa('MT::Entry');
            my $entry = $entry_class->load($place->object_id)
                or next;
            my %entry_data = (
                id    => $place->object_id,
                class => $entry->class_type,
                entry => $entry,
                title => $entry->title,
            );
            if (my $ts = $entry->authored_on) {
                $entry_data{authored_on_ts} = $ts;
                $entry_data{authored_on_formatted} =
                  format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $ts, undef,
                    $app->user ? $app->user->preferred_language : undef );
            }
            if (my $ts = $entry->created_on) {
                $entry_data{created_on_ts} = $ts;
                $entry_data{created_on_formatted} =
                  format_ts( MT::App::CMS::LISTING_DATETIME_FORMAT(), $ts, undef,
                    $app->user ? $app->user->preferred_language : undef );
            }
            push @appears_in, \%entry_data;
        }
        if (4 == @appears_in) {    
            pop @appears_in;
            $param->{appears_in_more} = 1;
        }
        $param->{appears_in} = \@appears_in if @appears_in;
### New <

        my $ts = $obj->created_on;
        if ( my $by = $obj->created_by ) {
            my $user = MT::Author->load($by);
            $row->{created_by} = $user ? $user->name : $app->translate('(user deleted)');
        }
        if ($ts) {
            $row->{created_on_formatted} =
              format_ts( MT::App::CMS::LISTING_DATE_FORMAT(), $ts, $blog, $app->user ? $app->user->preferred_language : undef );
            $row->{created_on_time_formatted} =
              format_ts( MT::App::CMS::LISTING_TIMESTAMP_FORMAT(), $ts, $blog, $app->user ? $app->user->preferred_language : undef );
            $row->{created_on_relative} = relative_date( $ts, time, $blog );
        }

        @$row{keys %$meta} = values %$meta;
        $row->{metadata_json} = MT::Util::to_json($meta);
        $row;
    };
}

sub asset_table {
    my ($cb, $app, $tmpl) = @_;

    my $old = <<HERE;
                <th class="created-on"><__trans phrase="Created On"></th>
            </tr>
        </mt:setvarblock>
HERE
    $old = quotemeta($old);

    my $new = <<HERE;
                <th class="created-on"><__trans phrase="Created On"></th>
                <th class="created-on"><__trans phrase="Appears in..."></th>
            </tr>
        </mt:setvarblock>
HERE

    $$tmpl =~ s/$old/$new/;

    my $old = <<HERE;
            </tr>
    <mt:if __last__>
        </tbody>
HERE
    $old = quotemeta($old);

    my $new = <<HERE;
                <td>
    <mt:if name="appears_in">
        <mt:loop name="appears_in">
        <mt:if name="__first__">
        <ul>
        </mt:if>
            <li><a href="<mt:var name="script_url">?__mode=edit&amp;_type=<mt:var name="class">&amp;blog_id=<mt:var name="blog_id" escape="url">&amp;id=<mt:var name="id" escape="url">" class="icon-left icon-<mt:var name="class" lower_case="1">"><mt:var name="title" escape="html" default="..."></a></li>
        <mt:if name="__last__">
        </ul>
        </mt:if>
        </mt:loop>
        <mt:if name="appears_in_more">
        <p><a href="<mt:var name="script_url">?__mode=list_entry&amp;blog_id=<mt:var name="blog_id" escape="url">&amp;filter=asset_id&amp;filter_val=<mt:var name="id" escape="url">"><__trans phrase="Show all entries"></a></p>
        <p><a href="<mt:var name="script_url">?__mode=list_page&amp;blog_id=<mt:var name="blog_id" escape="url">&amp;filter=asset_id&amp;filter_val=<mt:var name="id" escape="url">"><__trans phrase="Show all pages"></a></p>
        </mt:if>
    <mt:else>
        <span class="hint"><__trans phrase="This asset has not been used."></span>
    </mt:if>
                </td>
            </tr>
    <mt:if __last__>
        </tbody>
HERE

    $$tmpl =~ s/$old/$new/;
}

1;
