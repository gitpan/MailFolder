#!/usr/bin/perl       # -*-perl-*-

require 't/mbox.pl';

print "1..4\n";

okay_if(1, $folder = new Mail::Folder('mbox', full_folder()));
okay_if(2, $folder->qty == 2);
okay_if(3, $folder->close);

okay_if(4, Mail::Folder::_detect_folder_type(full_folder()) eq 'mbox');

1;
