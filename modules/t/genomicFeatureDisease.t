=head1 LICENSE
Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
     http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
=cut
use strict;
use warnings;

use Test::More;
use Bio::EnsEMBL::G2P::GenomicFeatureDisease;
use Bio::EnsEMBL::Test::MultiTestDB;
use Bio::EnsEMBL::Test::TestUtils;

my $multi = Bio::EnsEMBL::Test::MultiTestDB->new('homo_sapiens');

my $g2pdb = $multi->get_DBAdaptor('gene2phenotype');

my $gfda = $g2pdb->get_GenomicFeatureDiseaseAdaptor;

my $dbID = 49;
my $genomic_feature_id = 1252;
my $disease_id = 216;
my $DDD_category_attrib = 32;
my $is_visible = 1;
my $panel = '38';

my $gfd = Bio::EnsEMBL::G2P::GenomicFeatureDisease->new(
  -genomic_feature_id => $genomic_feature_id,
  -disease_id => $disease_id,
  -DDD_category_attrib => $DDD_category_attrib,
  -is_visible => $is_visible,
  -panel => $panel,
  -adaptor => $gfda,
);

ok($gfd->genomic_feature_id == $genomic_feature_id, 'genomic_feature_id');
ok($gfd->disease_id == $disease_id, 'disease_id');
ok($gfd->DDD_category_attrib == $DDD_category_attrib, 'DDD_category_attrib');
ok($gfd->DDD_category eq 'confirmed DD gene', 'DDD_category');
ok($gfd->is_visible == 1, 'is_visible');
ok($gfd->panel eq $panel, 'panel');


$gfd = $gfda->fetch_by_dbID($dbID);
my $GFDAs = $gfd->get_all_GenomicFeatureDiseaseActions();
ok(scalar @$GFDAs == 1, 'count genomic_feature_disease_actions');

my $gf = $gfd->get_GenomicFeature();
ok($gf->gene_symbol eq 'COL2A1', 'get_GenomicFeature');

my $disease = $gfd->get_Disease();
ok($disease->name eq 'KNIEST DYSPLASIA (KD)', 'get_Disease');

done_testing();
1;
