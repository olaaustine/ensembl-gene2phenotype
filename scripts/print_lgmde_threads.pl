use strict;
use warnings;

use Bio::EnsEMBL::Registry;

use FileHandle;

my $registry_file = '/Users/anja/Documents/G2P/ensembl.registry.mar2019';
my $registry = 'Bio::EnsEMBL::Registry';
$registry->load_all($registry_file);
my $dbh = $registry->get_DBAdaptor('human', 'gene2phenotype')->dbc->db_handle;


my $gfda = $registry->get_adaptor('human', 'gene2phenotype', 'GenomicFeatureDisease');

my $panel_adaptor = $registry->get_adaptor('human', 'gene2phenotype', 'Panel');
my $panels = $panel_adaptor->fetch_all;

# locus-genotype-mechanism-disease-evidence
#print_entries_with_more_than_one_action();

print_phenotype_overlap();

sub print_phenotype_overlap {
  my $threads = {};

  foreach my $panel (@$panels) {
    my $name = $panel->name;
    my $gfds = $gfda->fetch_all_by_panel($name);
    foreach my $gfd (sort { $a->get_GenomicFeature->gene_symbol cmp $b->get_GenomicFeature->gene_symbol } @$gfds) {
      my $gene = $gfd->get_GenomicFeature->gene_symbol;
      my $disease = $gfd->get_Disease->name;
      my $actions = $gfd->get_all_GenomicFeatureDiseaseActions; 
      if (scalar @$actions == 1) {
        my $action = $actions->[0];
        my $allelic_requirement = $action->allelic_requirement || 'NA'; 
        my $mutation_consequence = $action->mutation_consequence || 'NA';
        my $key = join(' ', $gene, $allelic_requirement, $mutation_consequence);
        $threads->{$key}->{$name}->{$disease} = $gfd->dbID;
      }
    }
  }
  print scalar keys %$threads, "\n";
  my $unique_threads = 0;
  my $duplicated_threads = 0;
  foreach my $thread (sort keys %$threads) {
    if (scalar keys %{$threads->{$thread}} > 1) {
      $duplicated_threads++;
      foreach my $panel (sort keys %{$threads->{$thread}}) {
        foreach my $disease (sort keys %{$threads->{$thread}->{$panel}}) {

        }
      }
    } else {
      $unique_threads++;
    }
  }

  $fh->close;
  print "Duplicated threads $duplicated_threads\n";
  print "Unique threads $unique_threads\n";



}


#create_lgmde_threads();

sub create_lgmde_threads {
  my $threads = {};

  my $fh = FileHandle->new("/Users/anja/Documents/G2P/lgmd/create_lgmde_threads", 'w');

  foreach my $panel (@$panels) {
    my $name = $panel->name;
    my $gfds = $gfda->fetch_all_by_panel($name);
    foreach my $gfd (sort { $a->get_GenomicFeature->gene_symbol cmp $b->get_GenomicFeature->gene_symbol } @$gfds) {
      my $gene = $gfd->get_GenomicFeature->gene_symbol;
      my $disease = $gfd->get_Disease->name;
      my $actions = $gfd->get_all_GenomicFeatureDiseaseActions; 
      if (scalar @$actions == 1) {
        my $action = $actions->[0];
        my $allelic_requirement = $action->allelic_requirement || 'NA'; 
        my $mutation_consequence = $action->mutation_consequence || 'NA';
        my $key = join(' ', $gene, $allelic_requirement, $mutation_consequence);
        $threads->{$key}->{$name}->{$disease} = 1;
      }
    }
  }
  print scalar keys %$threads, "\n";
  my $unique_threads = 0;
  my $duplicated_threads = 0;
  foreach my $thread (sort keys %$threads) {
    if (scalar keys %{$threads->{$thread}} > 1) {
      $duplicated_threads++;
      print $fh $thread, "\n";
      foreach my $panel (sort keys %{$threads->{$thread}}) {
        print $fh "    $panel\n";
        foreach my $disease (sort keys %{$threads->{$thread}->{$panel}}) {
          print $fh "        $disease\n"; 
        }
      }
    } else {
      $unique_threads++;
    }
  }

  $fh->close;
  print "Duplicated threads $duplicated_threads\n";
  print "Unique threads $unique_threads\n";

}


  





sub print_entries_with_more_than_one_action {

  my $fh = FileHandle->new("/Users/anja/Documents/G2P/lgmd/entries_with_more_than_one_action", 'w');

  foreach my $panel (@$panels) {
    my $name = $panel->name;
    my $gfds = $gfda->fetch_all_by_panel($name);
    print $fh $name, ' Entries: ', scalar @$gfds, "\n";
    foreach my $gfd (sort { $a->get_GenomicFeature->gene_symbol cmp $b->get_GenomicFeature->gene_symbol } @$gfds) {
      my $actions = $gfd->get_all_GenomicFeatureDiseaseActions; 
      if (scalar @$actions > 1) {
        my $gene = $gfd->get_GenomicFeature->gene_symbol;
        my $disease = $gfd->get_Disease->name;
        print $fh "    $gene $disease\n";
        foreach my $action (sort {$a->allelic_requirement cmp $b->allelic_requirement} @$actions) {
          my $allelic_requirement = $action->allelic_requirement; 
          my $mutation_consequence = $action->mutation_consequence;
            print $fh "        $allelic_requirement, $mutation_consequence\n";
        }
      }
    }
  }
  $fh->close;
}
