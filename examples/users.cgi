#!/usr/env perl
# Example CGI script.
#
use 5.10.1;
use strict;
use warnings;
use utf8;

use File::Basename 'dirname';
use Cwd;
use lib (Cwd::abs_path(dirname(__FILE__)).'/lib');
