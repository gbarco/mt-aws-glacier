# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

package App::MtAws::ChildWorker;

use App::MtAws::LineProtocol;
use App::MtAws::GlacierRequest;
use strict;
use warnings;
use utf8;
use File::Basename;
use File::Path;
use Carp;
use IO::Select;

sub new
{
    my ($class, %args) = @_;
    my $self = \%args;
    $self->{fromchild}||die;
    $self->{tochild}||die;
    $self->{options}||die;
    bless $self, $class;
    return $self;
}

sub process
{
	my ($self) = @_;
	
	my $tochild = $self->{tochild};
	my $fromchild = $self->{fromchild};
	my $disp_select = IO::Select->new();
	$disp_select->add($tochild);
	while (my @ready = $disp_select->can_read()) {
	    for my $fh (@ready) {
			if (eof($fh)) {
				$disp_select->remove($fh);
				return;
			}
			my ($taskid, $action, $data, $attachmentref) = get_command($fh);
			my $result = undef;
			
			my $console_out = undef;
			if ($action eq 'create_upload') {
				 # TODO: partsize confusing, need use another name for option partsize. partsize Amazon Upload partsize vs Download 'Range' partsize
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $uploadid = $req->create_multipart_upload($data->{partsize}, $data->{relfilename}, $data->{mtime});
				confess unless $uploadid;
				$result = { upload_id => $uploadid };
				$console_out = "Created an upload_id $uploadid";
			} elsif ($action eq "upload_part") {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->upload_part($data->{upload_id}, $attachmentref, $data->{start}, $data->{part_final_hash});
				return undef unless $r;
				$result = { uploaded => $data->{start} } ;
				$console_out = "Uploaded part for $data->{filename} at offset [$data->{start}]";
			} elsif ($action eq 'finish_upload') {
				# TODO: move vault to task, not to options!
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $archive_id = $req->finish_multipart_upload($data->{upload_id}, $data->{filesize}, $data->{final_hash});
				return undef unless $archive_id;
				$result = {
					final_hash => $data->{final_hash},
					archive_id => $archive_id,
					journal_entry => {
						type=> 'CREATED',
						'time' => $req->{last_request_time},
						archive_id => $archive_id,
						size => $data->{filesize},
						mtime => $data->{mtime},
						treehash => $data->{final_hash},
						relfilename => $data->{relfilename}
					},
				};
				$console_out = "Finished $data->{filename} hash [$data->{final_hash}] archive_id [$archive_id]";
			} elsif ($action eq 'delete_archive') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->delete_archive($data->{archive_id});
				return undef unless $r;
				$result = {
					journal_entry => {
						type=> 'DELETED',
						'time' => $req->{last_request_time},
						archive_id => $data->{archive_id},
						relfilename => $data->{relfilename}
						}
				};
				$console_out = "Deleted $data->{relfilename} archive_id [$data->{archive_id}]";
			} elsif ($action eq 'retrieval_download_job') {
				mkpath(dirname($data->{filename}));
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieval_download_job($data->{jobid}, $data->{filename});
				return undef unless $r;
				$result = { response => $r };
				$console_out = "Download Archive $data->{filename}";
			} elsif ($action eq 'inventory_download_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieval_download_to_memory($data->{job_id});
				return undef unless $r;
				$result = { response => $r };
				$console_out = "Downloaded inventory in JSON format";
			} elsif ($action eq 'retrieve_archive') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieve_archive( $data->{archive_id});
				return undef unless $r;
				$result = {
					journal_entry => {
						type=> 'RETRIEVE_JOB',
						'time' => $req->{last_request_time},
						archive_id => $data->{archive_id},
						job_id => $r,
						}
				};
				$console_out = "Retrieved Archive $data->{archive_id}";
			} elsif ($action eq 'retrieval_fetch_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieval_fetch_job($data->{marker});
				confess unless $r;
				$result = { response => $r };
				$console_out = "Retrieved Job List";
			} elsif ($action eq 'inventory_fetch_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieval_fetch_job($data->{marker});
				confess unless $r;
				$result = { response => $r };
				$console_out = "Fetched job list for inventory retrieval";
			} elsif ($action eq 'retrieve_inventory_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->retrieve_inventory();
				confess unless $r;
				$result = { job_id => $r };
				$console_out = "Retrieved Inventory, job id $r";
			} elsif ($action eq 'create_vault_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->create_vault($data->{name});
				confess unless $r;
				$result = { };
				$console_out = "Created vault $data->{name}";
			} elsif ($action eq 'delete_vault_job') {
				my $req = App::MtAws::GlacierRequest->new($self->{options});
				my $r = $req->delete_vault($data->{name});
				confess unless $r;
				$result = { };
				$console_out = "Deleted vault $data->{name}";
			} else {
				die $action;
			}
			$result->{console_out}=$console_out;
			send_response($fromchild, $taskid, $result);
	    }
	}
}


sub get_command
{
  my ($fh) = @_;
  my $response = <$fh>;
  chomp $response;
  my ($taskid, $action, $attachmentsize, $data_e) = split(/\t/, $response);
  my $attachment = undef;
  if ($attachmentsize) {
  	read $fh, $attachment, $attachmentsize;
  }
  my $data = decode_data($data_e);
  return ($taskid, $action, $data, $attachment ? \$attachment : undef);
}


sub send_response
{
  my ($fh, $taskid, $data) = @_;
  my $data_e = encode_data($data);
  my $line = "$$\t$taskid\t$data_e\n";
  print $fh $line;
}



1;
