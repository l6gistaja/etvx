#!/usr/bin/perl
use POSIX qw/strftime/;
use DBI;
# you also need DBD:SQLite;
$rfc822 = '%a, %d %b %Y %H:%M:%S %Z';

print '<?xml version="1.0" encoding="UTF-8"?>'."\n";
print '<rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/">'."\n";
print '<channel>'."\n";
print '<title>ETVx MRSS export</title>'."\n";
print '<pubDate>'.strftime($rfc822,localtime).'</pubDate>'."\n";

my $dbh = DBI->connect("dbi:SQLite:development.sqlite3", "", "",
{RaiseError => 1, AutoCommit => 1});
my $sth = $dbh->prepare("select b.filename, b.name, b.description, c.name as cname, t1ts-t0ts as duration, c.id as cid, b.t0ts, b.id from broadcasts b, channels c where (b.filename is not null or b.filename <> '') and b.channel_id=c.id");
$sth->execute();
while(my $result = $sth->fetchrow_hashref()) {
    print '<item>'."\n";
    print '<title>'.$result->{'name'}.'</title>'."\n";
    if($result->{'description'} ne '') {
        print '<description>'.$result->{'description'}.'</description>'."\n";
    }
    print '<pubDate>'.strftime($rfc822,gmtime($result->{'t0ts'})).'</pubDate>'."\n";
    print '<media:content url="'.$result->{'filename'}.'" duration="'.$result->{'duration'}.'" medium="video"/>'."\n";
    print '<guid>jae/etvx/c_'.sprintf("%x",$result->{'cid'})
        .'/t_'.sprintf("%x",$result->{'t0ts'}/60)
        .'_i_'.sprintf("%x",$result->{'id'}).'</guid>'."\n";
    #print '<media:keywords>'.$result->{'cname'}.'</media:keywords>'."\n";
    print '</item>'."\n";
}

$sth->finish();
$dbh->disconnect;
print '</channel>'."\n";
print '</rss>'."\n";

