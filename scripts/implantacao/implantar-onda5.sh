#!/bin/bash
# RAIZ — Onda 5 (Knowledge Hub). Uso: cd ~/Downloads/raiz-onda5 && bash implantar-onda5.sh
set -u
ORG=radar
TESTES="RaizKnowledgeServiceTest RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
cd "$(dirname "$0")"; mkdir -p saida
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done
passo "0/5 Documentos funcionais existentes (somente leitura)"
sf data query --target-org $ORG --query "SELECT COUNT(Id) total FROM Business_Rule__c" 2>&1 | tee saida/00-documentos-antes.txt
passo "1/5 Validacao (dry-run)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/01-validacao.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/5 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/02-deploy.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "deploy" 02-deploy.txt
passo "3/5 Permissao de aprovador para o seu usuario"
sf org assign permset --name RAIZ_Aprovador --target-org $ORG 2>&1 | tee saida/03-permset.txt
passo "4/5 Documentos de demonstracao"
sf apex run --file scripts/apex/seed-onda5.apex --target-org $ORG > saida/04-seed-bruto.txt 2>&1 || falhou "carga" 04-seed-bruto.txt
grep -E "RAIZ |Error|EXCEPTION" saida/04-seed-bruto.txt | sed 's/.*DEBUG|//' | tee saida/04-seed.txt
passo "5/5 Verificacao"
sf apex run --file scripts/apex/verificar-onda5.apex --target-org $ORG > saida/05-verificar-bruto.txt 2>&1
grep -E "RAIZ |Error|EXCEPTION" saida/05-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/05-verificar.txt
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/06-testes.txt 2>&1
grep -E "Outcome|Pass Rate|Tests Ran|RaizKnowledgeService |RaizCockpitService " saida/06-testes.txt | tee saida/06-resumo.txt
echo; echo "OK — abra: sf org open --path lightning/n/RAIZ_Knowledge_Hub --target-org $ORG"
