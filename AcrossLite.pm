# Copyright (c) 2002 Douglas Sparling. All rights reserved. This program is free
# software; you can redistribute it and/or modify it under the same terms
# as Perl itself.

package Convert::AcrossLite;

use strict;
use Carp;
use vars qw($VERSION);

$VERSION = '0.03';

sub new {
    my $class = shift;
    my %conf = @_;

    my $self = {};
    $self->{in_file} = $conf{in_file} || 'Default.puz';
    $self->{is_parsed} = 0;

    bless($self, $class);
    return $self;
}

sub in_file {
    my($self) = shift;
    if(@_) { $self->{in_file} = shift }
    return $self->{in_file};
}

sub out_file {
    my($self) = shift;
    if(@_) { $self->{out_file} = shift }
    return $self->{out_file};
}

sub puz2text {
    my($self) = shift;
    my $text;

    # Parse puz file
    _parse_file($self) unless $self->{is_parsed};

    # Format across clues
    my @aclues = split("\n", $self->{aclues});
    foreach my $aclue(@aclues) {
        $aclue =~ s/\d+\s+-\s+//;
        $aclue = "\t$aclue";
    }
    $self->{aclues} = join("\n",@aclues);

    # Format down clues
    my @dclues = split("\n", $self->{dclues});
    foreach my $dclue(@dclues) {
        $dclue =~ s/\d+\s+-\s+//;
        $dclue = "\t$dclue";
    }
    $self->{dclues} = join("\n",@dclues);

    $text = "<ACROSS PUZZLE>\n"; 
    $text .= "<TITLE>\n";
    $text .= "\t$self->{title}\n";
    $text .= "<AUTHOR>\n";
    $text .= "\t$self->{author}\n";
    $text .= "<COPYRIGHT>\n";
    $text .= "\t$self->{copyright}\n";
    $text .= "<SIZE>\n";
    $text .= "\t$self->{rows}x$self->{columns}\n";
    $text .= "<GRID>\n";
    my $solref = $self->{solution};
    my @sol = @$solref;
    foreach my $sol (@sol) {
        $text .= "\t$sol\n";
    }
    $text .= "<ACROSS>\n";
    $text .= "$self->{aclues}\n";
    $text .= "<DOWN>\n";
    $text .= "$self->{dclues}\n";

    if( defined $self->out_file ) {
        my $PUZ_OUT = $self->out_file;

        open FH, ">$PUZ_OUT" or croak "Can't open $PUZ_OUT: $!";
        print FH $text;
        close FH;
    } else {
        return $text;
    }
}

sub parse_file {
    my($self) = shift;
    _parse_file($self);
}

sub _parse_file {
    my($self) = shift;
    my($buf, $parse_word, $oe);
    my($aclues, $dclues);

    my $PUZ_IN = $self->{in_file};

    open FH, $PUZ_IN or croak "Can't open $PUZ_IN: $!";
    binmode(FH); # Be nice to windoz

    # Skip unneeded data
    seek(FH, 44, 0);

    # Width and Height
    read(FH, $buf, 2);
    my ($width, $height) = unpack "C C", $buf;
    $self->{rows} = $height;
    $self->{columns} = $width;

    # Skip more unneeded data
    read(FH, $buf, 6);

    # Solution
    my @solution;
    for(my $j=0; $j<$height; $j++) {
        read(FH, $solution[$j], $width);
    }
    $self->{solution} = \@solution;

    # Diagram
    my @diagram;
    for(my $j=0;$j<$height;$j++) {
        read(FH, $diagram[$j], $width);
    }
    $self->{diagram} = \@diagram;

    # Title
    $oe = 0;
    while(1) {
        read(FH, $buf, 1) or last;
        my ($char) = unpack "C", $buf;
        last if $char == 0;
        $parse_word .= $buf;
    }
    $parse_word =~ s/^\s+//;
    $parse_word =~ s/\s+$//;
    $self->{title} = $parse_word;

    # Author
    $parse_word = '';
    $oe = 0;
    while(1) {
        read(FH, $buf, 1) or last;
        my ($char) = unpack "C", $buf;
        last if $char == 0;
        $parse_word .= $buf;
    }
    $parse_word =~ s/^\s+//;
    $parse_word =~ s/\s+$//;
    $self->{author} = $parse_word;

    # Copyright
    $parse_word = '';
    $oe = 0;
    while(1) {
        read(FH, $buf, 1) or last;
        my ($char) = unpack "C", $buf;
        last if $char == 0;
        $parse_word .= $buf;
    }
    $parse_word =~ s/^\s+//;
    $parse_word =~ s/\s+$//;
    $self->{copyright} = $parse_word;

    # Clues
    my ($apos,$dpos);
    my $ccount = 0;
    my $mcount = 0;

    for (my $j=0;$j<$height;$j++) {
        my $rowtext;
        for(my $k=0;$k<$width;$k++) {
            # Check position for across number
            # Left edge non-black followed by non-black
            my $anum = 0; # across number
            if( ($k == 0 &&
                 substr($diagram[$j],$k,1) eq '-' &&
                 substr($diagram[$j],$k+1,1) eq '-') ||
              # Previous black - nonblack - nonblack
                ( ($k+1)<$width &&
                  ($k-1)>=0 &&
                  substr($diagram[$j],$k,1) eq '-' &&
                  substr($diagram[$j],$k-1,1) eq '.' &&
                  substr($diagram[$j],$k+1,1) eq '-' ) ) {
                      $ccount++;
                      $anum = $ccount;
            }


            # Check position for down number
            my $dnum = 0;
            if( ($j == 0 &&
                 substr($diagram[$j],$k,1) eq '-' &&
                 substr($diagram[$j+1],$k,1) eq '-') ||
              # Black above - nonblack - nonblack below
                ( ($j-1)>=0&&
                  ($j+1)<$height &&
                  substr($diagram[$j],$k,1) eq '-' &&
                  substr($diagram[$j-1],$k,1) eq '.' &&
                  substr($diagram[$j+1],$k,1) eq '-' ) ) {
                      # Don't double number the same space
                      if( $anum == 0 ) {
                          $ccount++;
                      }
                      $dnum = $ccount;
            }

            # Get clues
            # Across
            if( $anum != 0 ) {
                my $tmp;
                $parse_word = '';
                $oe = 0;
                while(1) {
                    read(FH, $buf, 1) or last;
                    my ($char) = unpack "C", $buf;
                    last if $char == 0;
                    $parse_word .= $buf;
                }
                $parse_word =~ s/^\s+//;
                $parse_word =~ s/\s+$//;
                $tmp = $parse_word;
                $aclues .= "$anum - $tmp\n";
            }
 
            # Down
            if( $dnum != 0 ) {
                my $tmp;
                $parse_word = '';
                $oe = 0;
                while(1) {
                    read(FH, $buf, 1) or last;
                    my ($char) = unpack "C", $buf;
                    last if $char == 0;
                    $parse_word .= $buf;
                }
                $parse_word =~ s/^\s+//;
                $parse_word =~ s/\s+$//;
                $tmp = $parse_word;
                $dclues .= "$dnum - $tmp\n";
            }
        }
    }
    close FH;

    $self->{aclues} = $aclues;
    $self->{dclues} = $dclues;
    $self->{is_parsed} = 1;

}

sub is_parsed{ 
    my($self) = @_;
    return $self->{is_parsed};
}

sub get_rows {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{rows};
}

sub get_columns {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{columns};
}

sub get_solution {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    my $solref = $self->{solution};
    my @sol = @$solref;
    return @sol;
}

sub get_diagram {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    my $diagref = $self->{diagram};
    my @diag = @$diagref;
    return @diag;
}

sub get_title {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{title};
}

sub get_author {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{author};
}

sub get_copyright {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{copyright};
}

sub get_across_clues {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{aclues};
}

sub get_down_clues {
    my($self) = @_;
    _parse_file($self) unless $self->{is_parsed}; 
    return $self->{dclues};
}


1;

__END__

=head1 NAME

Convert::AcrossLite - Convert binary AcrossLite puzzle files to text.

=head1 SYNOPSIS

  use Convert::AcrossLite;

  my $ac = Convert::AcrossLite->new();
  $ac->in_file('/home/doug/puzzles/Easy.puz');
  $ac->out_file('/home/doug/puzzles/Easy.txt');
  $ac->puz2text;

  or

  use Convert::AcrossLite;

  my $ac = Convert::AcrossLite->new();
  $ac->in_file('/home/doug/puzzles/Easy.puz');
  my $text = $ac->puz2text;

  or

  use Convert::AcrossLite;

  my $ac = Convert::AcrossLite->new();
  $ac->in_file('/home/doug/puzzles/Easy.puz');
  my $ac->parse_file;
  my $title = $ac->get_title;
  my $author = $ac->get_author;
  my $copyright = $ac->get_copyright;
  my @solution = $ac->get_solution;
  my @diagram = $ac->get_diagram;
  my $across_clues = $ac->get_across_clues;
  my $down_clues = $ac->get_down_clues;

=head1 DESCRIPTION

Convert::AcrossLite is used to convert binary AcrossLite puzzle files to text.

Convert::AcrossLite is loosely based on the C program written by Bob Newell (http://www.gtoal.com/wordgames/gene/AcrossLite).

=head1 CONSTRUCTOR

=head2 new

This is the contructor. You can pass the full path to the puzzle input file.

  my $ac = Convert::AcrossLite->new(in_file => '/home/doug/puzzles/Easy.puz');

The default value is 'Default.puz'.

=head1 METHODS

=head2 in_file

This method returns the current puzzle input path/filename. 

  my $in_filename = $ac->in_file;

You may also set the puzzle input file by passing the path/filename.

  $ac->in_file('/home/doug/puzzles/Easy.puz');

=head2 out_file

This method returns the current puzzle output path/filename. 

  my $out_filename = $ac->out_file;

You may also set the puzzle output file by passing the path/filename.

  $ac->out_file('/home/doug/puzzles/Easy.txt');


=head2 puz2text

This method will produce a basic text file in the same format as the easy.txt file provided with AcrossLite. This method will read the input file set by in_file and write to the file set by out_file. 

  $ac->puz2text;

If out_file is not set, then the text is returned.

  print $ac->puz2text;

  or

  my $text = $ac->puz2text;

=head2 parse_file

This method will parse the puzzle file by calling _parse_file. 

=head2 _parse_file

This helper method does the actual parsing of the puz file.

=head2 is_parsed

This method returns file parse status: 0 if input file has not been parsed, 1 if input file has been parsed.

=head2 get_rows

This method returns the number of rows in puzzle.

  my $rows = $ac->get_rows;

=head2 get_columns

This method returns the number of columns in puzzle.

  my $columns = $ac->get_columns;

=head2 get_solution

This method returns the puzzle solution.

  my @solution = $ac->get_solution;

=head2 get_diagram

This method returns the puzzle solution diagram.

  my @solution = $ac->get_diagram;

=head2 get_title

This method returns the puzzle title.

  my $title = $ac->get_title;

=head2 get_author

This method returns the puzzle author.

  my $author = $ac->get_author;

=head2 get_copyright

This method returns the puzzle copyright.

  my $copyright = $ac->get_copyright;

=head2 get_across_clues

This method returns the puzzle across clues.

  my $across_clues = $ac->get_across_clues;

=head2 get_down_clues

This method returns the puzzle down clues.

  my $down_clues = $ac->get_down_clues;

=head1 AUTHOR

Doug Sparling E<lt>F<doug@dougsparling.com>E<gt>

=head1 COPYRIGHT

Copyright (c) 2002 Douglas Sparling. All rights reserved. This program is free
software; you can redistribute it and/or modify it under the same terms
as Perl itself.

=cut
