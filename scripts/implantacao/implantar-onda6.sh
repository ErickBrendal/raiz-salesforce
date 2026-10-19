#!/bin/bash
# RAIZ 4.0 — Onda 6 (Cadastro guiado). Uso: cd ~/Downloads/raiz-onda6 && bash implantar-onda6.sh
set -u
ORG=radar
TESTES="RaizJourneyServiceTest RaizGovernancaServiceTest RaizKnowledgeServiceTest RaizCockpitServiceTest RaizMitigationServiceTest RaizSimulationServiceTest RaizRiskEngineTest"
cd "$(dirname "$0")"; mkdir -p saida
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }
TL=""; CN=""; for t in $TESTES; do TL="$TL --tests $t"; CN="$CN --class-names $t"; done
passo "1/5 Validacao (dry-run)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/01-validacao.txt 2>&1
R=$?; grep -E "Status:|Successful:|Failed:|Error|Passing|Failing|Deploy ID" saida/01-validacao.txt | head -40
[ $R -eq 0 ] || falhou "validacao" 01-validacao.txt
passo "2/5 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG --test-level RunSpecifiedTests $TL --wait 40 > saida/02-deploy.txt 2>&1
R=$?; grep -E "Status:|Components:|Successful:|Failed:|Passing|Failing|Deploy ID" saida/02-deploy.txt | head -20
[ $R -eq 0 ] || falhou "deploy" 02-deploy.txt
passo "3/5 Revisor Demo (usuario ficticio, decisao D4)"
read -r -p "E-mail que recebe o convite do Revisor Demo (Enter para pular): " EMAIL
if [ -n "$EMAIL" ]; then
  sed "s|__EMAIL__|$EMAIL|" scripts/apex/revisor-demo.apex > saida/revisor-demo.apex
  sf apex run --file saida/revisor-demo.apex --target-org $ORG > saida/03-revisor-bruto.txt 2>&1
  grep -E "RAIZ |Error|EXCEPTION" saida/03-revisor-bruto.txt | sed 's/.*DEBUG|//' | tee saida/03-revisor.txt
else
  echo "pulado"
fi
passo "4/5 Verificacao (somente leitura)"
sf apex run --file scripts/apex/verificar-onda6.apex --target-org $ORG > saida/04-verificar-bruto.txt 2>&1
grep -E "RAIZ |Error|EXCEPTION" saida/04-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/04-verificar.txt
passo "5/5 Testes com cobertura"
sf apex run test $CN --code-coverage --result-format human --target-org $ORG --wait 20 > saida/05-testes.txt 2>&1
grep -E "Outcome|Pass Rate|Tests Ran|Fail|RaizJourneyService |RaizGovernancaService " saida/05-testes.txt | head -20 | tee saida/05-resumo.txt
echo; echo "OK — abra: sf org open --path lightning/n/RAIZ_Cadastro_Guiado --target-org $ORG"
