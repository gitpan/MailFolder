#!/usr/bin/perl       # -*-perl-*-

require 't/emaul.pl';

print "1..7\n";
  
okay_if(1, $folder = new Mail::Folder('emaul', full_folder()));
okay_if(2, $folder->qty == 2);
okay_if(3, $folder->close);

require 't/all.pl';

okay_if(4, Mail::Folder::detect_folder_type(full_folder()) eq 'emaul');

okay_if(5, $folder = new Mail::Folder('emaul', full_folder(), NFSLock => 1));
okay_if(6, $folder->qty == 2);
okay_if(7, $folder->close);

1;
