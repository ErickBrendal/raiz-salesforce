#!/bin/bash
# RAIZ 4.0 — Ondas 9-10 (Integration Hub + Portfolio Demo Mode) e quality gate. Requer a Onda 8.
# Uso:  bash implantar-onda9.sh            deploy + inventario + testes + evidencias + verificacao
#       bash implantar-onda9.sh --github   depois de publicar o repositorio e a release v1.0.0
set -u
ORG=radar
TESTES="RaizGitHubServiceTest RaizEngineeringTest RaizGovernancaActionTest RaizJourneyServiceTest RaizGovernancaServiceTest RaizKnowledgeServiceTest RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
cd "$(dirname "$0")"; mkdir -p saida/deploys
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
resumo() { grep -aE "Status: (Succeeded|Failed|Canceled)|Passing|Failing|Deploy ID: " "$1" | sort -u | head -10; sed -n "/Component Failures/,/└/p;/Test Failures/,/└/p" "$1" | head -60; }
carga() { sf data upsert bulk --sobject "$1" --file "$2" --external-id "$3" --line-ending LF --target-org $ORG --wait 10 > "$4" 2>&1; grep -aoE "(Successful|Failed) records: [0-9]+" "$4" | tail -2 | tr '\n' ' '; echo; }
apex() { sf apex run --file "$1" --target-org $ORG > "$2" 2>&1; grep -aE "\|ERROR\|RAIZ |EXCEPTION|Error" "$2" | sed 's/.*DEBUG|//'; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done

if [ "${1:-}" = "--github" ]; then
  passo "GitHub: sincronizar e ligar a release v1.0.0 ao deploy"
  apex scripts/apex/github-onda9.apex saida/g1-github.txt | tee saida/g1-github-resumo.txt
  passo "Quality gate"
  apex scripts/apex/qualidade-onda9.apex saida/g2-qualidade.txt | tee saida/g2-qualidade-resumo.txt
  exit 0
fi

passo "0/8 A Onda 8 esta na org?"
sf data query --target-org $ORG --query "SELECT Name FROM ApexClass WHERE Name = 'RaizEngineeringVerifier'" > saida/00-pre.txt 2>&1
grep -q RaizEngineeringVerifier saida/00-pre.txt || { echo "XXXX Rode antes a Onda 8."; exit 1; }; echo ok
passo "1/8 Validacao (dry-run)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/01-validacao.txt 2>&1
R=$?; resumo saida/01-validacao.txt; [ $R -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/8 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/02-deploy.txt 2>&1
R=$?; resumo saida/02-deploy.txt; [ $R -eq 0 ] || falhou "deploy" 02-deploy.txt
ESTE=$(grep -aoE "Deploy ID: 0Af[A-Za-z0-9]{15}" saida/02-deploy.txt | tail -1 | awk '{print $3}')
[ -n "$ESTE" ] || falhou "Deploy ID nao encontrado na saida do deploy" 02-deploy.txt
passo "3/8 Inventario atualizado (Integracao e Demo Mode passam a Implementado)"
carga RAIZ_Engineering_Status__c inventario/01-funcionalidades.csv API_Name__c saida/03a.txt
carga RAIZ_Engineering_Status__c inventario/02-componentes.csv API_Name__c saida/03b.txt
passo "4/8 Implantacao deste deploy"
sf project deploy report --job-id "$ESTE" --target-org $ORG --json > saida/deploys/dep-$ESTE.json 2>/dev/null
python3 scripts/py/implantacoes.py saida/deploys saida/implantacoes.csv "$ESTE=Ondas 9-10"
carga RAIZ_Implantacao__c saida/implantacoes.csv Deploy_Id__c saida/04.txt
passo "5/8 Testes com cobertura"
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/05-testes.txt 2>&1
grep -aE "Outcome|Pass Rate|Tests Ran|Fail|RaizGitHubService |RaizEngineering" saida/05-testes.txt | head -20 | tee saida/05-resumo.txt
passo "6/8 Evidencias do sf CLI (LWC e cobertura)"
sf data query --target-org $ORG --result-format csv --query "SELECT API_Name__c, Tipo_Componente__c FROM RAIZ_Engineering_Status__c WHERE Nivel__c = 'Componente'" > saida/inv.csv 2>/dev/null
sf data query --use-tooling-api --target-org $ORG --result-format csv --query "SELECT DeveloperName FROM LightningComponentBundle WHERE NamespacePrefix = null" > saida/lwc.csv 2>/dev/null
sf data query --use-tooling-api --target-org $ORG --result-format csv --query "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate" > saida/cobertura.csv 2>/dev/null
python3 scripts/py/evidencias.py saida/inv.csv saida/lwc.csv saida/cobertura.csv saida/evidencias.csv
carga RAIZ_Evidencia__c saida/evidencias.csv Chave__c saida/06.txt
passo "7/8 GitHub (antes de publicar o repositorio, o esperado e 404)"
apex scripts/apex/github-onda9.apex saida/07-github.txt | tee saida/07-github-resumo.txt
passo "8/8 Quality gate"
apex scripts/apex/qualidade-onda9.apex saida/08-qualidade.txt | tee saida/08-qualidade-resumo.txt
echo; echo "OK — abra: sf org open --path lightning/n/RAIZ_Portfolio_Demo --target-org $ORG"
