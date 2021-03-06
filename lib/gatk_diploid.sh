#!/bin/bash
## Author S. Monzon
## version v2.0

# Test whether the script is being executed with sge or not.
if [ -z $SGE_TASK_ID ]; then
    	use_sge=0
else
    	use_sge=1
fi


# Exit immediately if a pipeline, which may consist of a single simple command, a list, or a compound command returns a non-zero status
set -e
# Treat unset variables and parameters other than the special parameters ‘@’ or ‘*’ as an error when performing parameter expansion. An error message will be written to the standard error, and a non-interactive shell will exit
set -u
set -x

## Usage

if [ $# != 21 -a "$use_sge" == "1" ]; then
    	echo "usage: ............"
    	exit
fi

#Print a trace of simple commands, for commands, case commands, select commands, and arithmetic for commands and their arguments or associated word lists after they are expanded and before they are executed
set -x
echo `date`

# Variables

DIR_BAM=$1
THREADS=$2
REF_PATH=$3
OUTPUT_DIR=$4
KNOWN_SNPS=$5
KNOWN_INDELS=$6
SNP_GOLD=$7
BAM_NAMES=$8
OUTPUT_VCF_NAME=${9}
OUTPUT_SNPS_NAME=${10}
OUTPUT_SNPS_NAME_FIL=${11}
OUTPUT_INDELS_NAME=${12}
OUTPUT_INDELS_NAME_FIL=${13}
OUTPUT_VCF_FIL_NAME=${14}
OUTPUT_VCF_PHASE_NAME=${15}
OUTPUT_VCF_BACKED_NAME=${16}
OUTPUT_VCF_GTPOS=${17}
OUTPUT_VCF_GTPOS_FIL=${18}
OUTPUT_VCF_GTPOS_FIL_ANNOT=${19}
GATK_PATH=${20}
PED_FILE=${21}

mkdir -p $OUTPUT_DIR/variants
echo $BAM_NAMES | tr ":" "\n" | awk -v prefix=$DIR_BAM '{print prefix "/" $0}' > $OUTPUT_DIR/bam.list

java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
       -T HaplotypeCaller \
       -R $REF_PATH \
       -I $OUTPUT_DIR/bam.list \
       -o $OUTPUT_DIR/variants/$OUTPUT_VCF_NAME \
       --dbsnp $KNOWN_SNPS \
       -stand_call_conf 30.0 \
       -stand_emit_conf 10.0 \
       -S LENIENT \
       -log $OUTPUT_DIR/$OUTPUT_VCF_NAME-HaplotypeCaller.log
 #-ped $PED_FILE \
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
       -R $REF_PATH \
       -T SelectVariants \
       -V $OUTPUT_DIR/variants/$OUTPUT_VCF_NAME \
       -o $OUTPUT_DIR/variants/$OUTPUT_SNPS_NAME \
       -selectType SNP \
       -nt $THREADS \
       -S LENIENT \
       -log $OUTPUT_DIR/$OUTPUT_VCF_NAME-selectSNP.log


java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
 	-R $REF_PATH \
 	-T VariantFiltration \
 	-V $OUTPUT_DIR/variants/$OUTPUT_SNPS_NAME \
 	-o $OUTPUT_DIR/variants/$OUTPUT_SNPS_NAME_FIL \
 	--clusterWindowSize 10 \
 	--filterExpression "MQ < 40" \
 	--filterName "RMSMappingQuality" \
 	--filterExpression "DP <5 " \
 	--filterName "LowCoverage" \
 	--filterExpression "QD <2.0 " \
 	--filterName "LowQD" \
 	--filterExpression "FS >60.0 " \
 	--filterName "p-value StrandBias" \
	--filterExpression "MQRankSum < -12.5" \
	--filterName "MappingQualityRankSumTest" \
	--filterExpression "ReadPosRankSum < -8.0" \
	--filterName "VariantReadPosEnd" \
	--filterExpression "SOR > 4.0" \
	--filterName "StrandOddRank" \
 	-S LENIENT \
 	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-filterSNPs.log

echo -e "Select and Filter Indels"
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
 	-R $REF_PATH \
 	-T SelectVariants \
 	-V $OUTPUT_DIR/variants/$OUTPUT_VCF_NAME \
 	-o $OUTPUT_DIR/variants/$OUTPUT_INDELS_NAME \
 	-selectType INDEL \
 	-nt $THREADS \
 	-S LENIENT \
 	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-selectIndels.log

java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
 	-T VariantFiltration \
 	-R $REF_PATH \
 	-V $OUTPUT_DIR/variants/$OUTPUT_INDELS_NAME \
 	-o $OUTPUT_DIR/variants/$OUTPUT_INDELS_NAME_FIL \
 	--filterExpression "QD < 2.0 || FS > 200.0 || ReadPosRankSum < -20.0 || SOR > 10.0" \
 	--filterName "IndelFilters" \
 	-S LENIENT \
 	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-filterIndels.log

echo -e "Combine snps and indels vcf"
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
       -R $REF_PATH \
       -T  CombineVariants \
	   --variant $OUTPUT_DIR/variants/$OUTPUT_SNPS_NAME_FIL \
       --variant $OUTPUT_DIR/variants/$OUTPUT_INDELS_NAME_FIL \
       --genotypemergeoption UNSORTED \
	   -o $OUTPUT_DIR/variants/$OUTPUT_VCF_FIL_NAME \
       -log $OUTPUT_DIR/$OUTPUT_VCF_NAME-CombineVCF.log

echo -e "Calculate PhaseByTransmission"
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
		-T PhaseByTransmission \
		-R $REF_PATH \
		-ped $PED_FILE \
		-pedValidationType SILENT \
		-V $OUTPUT_DIR/variants/$OUTPUT_VCF_FIL_NAME \
		-o $OUTPUT_DIR/variants/$OUTPUT_VCF_PHASE_NAME \
		-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-PhaseByTransmission.log
#
echo -e "Calculate ReadBackedPhasing"
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
		-T ReadBackedPhasing \
		-R $REF_PATH \
		-I $OUTPUT_DIR/bam.list \
		--variant $OUTPUT_DIR/variants/$OUTPUT_VCF_PHASE_NAME \
		-o $OUTPUT_DIR/variants/$OUTPUT_VCF_BACKED_NAME \
		--phaseQualityThresh 20.0 \
		-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-ReadBackedPhasing.log
#
echo -e "Genotype Refinement"
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
	-T CalculateGenotypePosteriors \
	-R $REF_PATH \
	--supporting $SNP_GOLD \
	-ped $PED_FILE \
	-pedValidationType SILENT \
	-V $OUTPUT_DIR/variants/$OUTPUT_VCF_BACKED_NAME \
	-o $OUTPUT_DIR/variants/$OUTPUT_VCF_GTPOS \
	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-GTPosteriors.log
#
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
	-T VariantFiltration \
	-R $REF_PATH \
	-V $OUTPUT_DIR/variants/$OUTPUT_VCF_GTPOS \
	-G_filter "GQ < 20.0" \
	-G_filterName "lowGQ" \
	-o $OUTPUT_DIR/variants/$OUTPUT_VCF_GTPOS_FIL \
	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-GTPOSFIL.log
#
java -XX:ParallelGCThreads=$NSLOTS -Djava.io.tmpdir=$TEMP $JAVA_RAM -jar $GATK_PATH/GenomeAnalysisTK.jar \
	-T VariantAnnotator \
	-R $REF_PATH \
	-V $OUTPUT_DIR/variants/$OUTPUT_VCF_GTPOS_FIL \
	-A PossibleDeNovo \
	-ped $PED_FILE \
	-pedValidationType SILENT \
	-o $OUTPUT_DIR/variants/$OUTPUT_VCF_GTPOS_FIL_ANNOT \
	-log $OUTPUT_DIR/$OUTPUT_VCF_NAME-GTPOSFILANNOT.log
