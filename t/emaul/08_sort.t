#!/usr/bin/perl       # -*-perl-*-

require 't/emaul.pl';

$sort_spec = sub { return($_[1]->get('subject') cmp $_[0]->get('subject')); };

print "1..4\n";

okay_if(1, $folder = new Mail::Folder('emaul', full_folder()));
@msgs = $folder->sort($sort_spec);
okay_if(2, $msgs[0] == 3);
okay_if(3, $msgs[1] == 1);
okay_if(4, $folder->close);

1;
