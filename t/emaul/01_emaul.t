#!/usr/bin/perl       # -*-perl-*-

require 't/emaul.pl';

print "1..4\n";
  
okay_if(1, $folder = new Mail::Folder('emaul', full_folder()));
okay_if(2, $folder->qty == 2);
okay_if(3, $folder->close);

require 't/all.pl';

okay_if(4, Mail::Folder::_detect_folder_type(full_folder()) eq 'emaul');

1;
