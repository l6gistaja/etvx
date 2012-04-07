#!/usr/bin/perl
use DBI;
# you also need DBD:SQLite;

print '<?xml version="1.0" encoding="UTF-8"?>'."\n";
print '<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">'."\n";
print '<channel>'."\n";
print '<title>ETVx MRSS export</title>'."\n";
my $dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});
my $sth = $dbh->prepare("select b.filename, b.name, b.description, c.name as cname, t1ts-t0ts as duration from broadcasts b, channels c where (b.filename is not null or b.filename <> '') and b.channel_id=c.id");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    print '<item>'."\n";
    print '<media:content url="'.$result->{'filename'}.'" duration="'.$result->{'duration'}.'"/>'."\n";
    print '<title>'.$result->{'name'}.'</title>'."\n";
    if($result->{'description'} ne '') {
        print '<description>'.$result->{'description'}.'</description>'."\n";
    }
    #print '<media:keywords>'.$result->{'cname'}.'</media:keywords>'."\n";
    print '</item>'."\n";
}

$sth->finish();
$dbh->disconnect;
print '</channel>'."\n";
print '</rss>'."\n";

