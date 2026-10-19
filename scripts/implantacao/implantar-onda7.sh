#!/bin/bash
# RAIZ 4.0 — Onda 7 (Automation Center). Requer a Onda 6 implantada.
# Uso: cd ~/Downloads/raiz-onda7 && bash implantar-onda7.sh
set -u
ORG=radar
TESTES="RaizGovernancaActionTest RaizJourneyServiceTest RaizGovernancaServiceTest RaizKnowledgeServiceTest RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
cd "$(dirname "$0")"; mkdir -p saida
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done
SO_DEMO=0; [ "${1:-}" = "--demo" ] && SO_DEMO=1
if [ $SO_DEMO -eq 0 ]; then
passo "0/6 A Onda 6 esta na org? (somente leitura)"
sf data query --target-org $ORG --query "SELECT Name FROM ApexClass WHERE Name IN ('RaizJourneyService','RaizGovernancaService')" > saida/00-pre.txt 2>&1
cat saida/00-pre.txt | grep -E "Raiz|Total"
grep -q RaizJourneyService saida/00-pre.txt || { echo "XXXX Rode antes a Onda 6 (implantar-onda6.sh)."; exit 1; }
passo "1/6 Validacao (dry-run)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/01-validacao.txt 2>&1
R=$?; grep -E "Status:|Successful:|Failed:|Error|Passing|Failing|Deploy ID" saida/01-validacao.txt | head -40
[ $R -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/6 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/02-deploy.txt 2>&1
R=$?; grep -E "Status:|Components:|Successful:|Failed:|Passing|Failing|Deploy ID" saida/02-deploy.txt | head -20
[ $R -eq 0 ] || falhou "deploy" 02-deploy.txt
passo "3/6 O Flow ficou ativo?"
sf data query --target-org $ORG --query "SELECT ApiName, IsActive FROM FlowDefinitionView WHERE ApiName = 'RAIZ_Governanca_Revisao'" 2>&1 | tee saida/03-flow.txt
if grep -q "false" saida/03-flow.txt; then
  echo "ATENCAO: o Flow foi implantado INATIVO (padrao de orgs de producao)."
  echo "Ative em: Configuracao > Fluxos > 'RAIZ - Governanca da revisao' > versao 1 > Ativar. Depois rode: bash implantar-onda7.sh --demo"
fi
fi
passo "4/6 Cenario de demonstracao (3 documentos ficticios pelo cadastro guiado)"
read -r -p "Criar os 3 documentos de demonstracao agora? [s/N] " OK
if [ "$OK" = "s" ] || [ "$OK" = "S" ]; then
  sf apex run --file scripts/apex/demo-onda7.apex --target-org $ORG > saida/04-demo-bruto.txt 2>&1
  grep -E "RAIZ |Error|EXCEPTION" saida/04-demo-bruto.txt | sed 's/.*DEBUG|//' | tee saida/04-demo.txt
else
  echo "pulado"
fi
passo "5/6 Verificacao (somente leitura)"
sf apex run --file scripts/apex/verificar-onda7.apex --target-org $ORG > saida/05-verificar-bruto.txt 2>&1
grep -E "RAIZ |Error|EXCEPTION" saida/05-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/05-verificar.txt
[ $SO_DEMO -eq 1 ] && exit 0
passo "6/6 Testes com cobertura"
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/06-testes.txt 2>&1
grep -E "Outcome|Pass Rate|Tests Ran|Fail|RaizGovernancaAction |RaizLog |RaizKnowledgeService |RaizCockpitService " saida/06-testes.txt | head -20 | tee saida/06-resumo.txt
echo; echo "OK — abra: sf org open --path lightning/n/RAIZ_Knowledge_Hub --target-org $ORG"
