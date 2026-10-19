#!/bin/bash
# =====================================================================
# RAIZ — Ondas 1 e 2 (motor de risco + simulador de ausencia)
# Uso:  cd ~/Downloads/raiz-onda1 && bash implantar-onda1.sh
# Etapas (para no primeiro erro; cada saida fica em ./saida):
#   1. validacao (dry-run) com os testes        -> nada muda na org
#   2. deploy real com os mesmos testes
#   3. permission set no seu usuario
#   4. carga de demonstracao idempotente
#   5. agenda o job diario e roda uma vez
#   6. verificacao somente leitura + cobertura
# Rollback de metadados: ~/Downloads/raiz-audit/backup-org (estado anterior).
# =====================================================================
set -u
ORG=radar
TESTES="RaizCockpitServiceTest RaizRiskEngineTest RaizSimulationServiceTest"
cd "$(dirname "$0")"
mkdir -p saida
passo() { echo; echo "==== $1"; }
falhou() { echo; echo "XXXX PAROU em: $1 — veja saida/$2"; exit 1; }

TL=""; for t in $TESTES; do TL="$TL --tests $t"; done

passo "1/6 Validacao (dry-run, nada e gravado)"
sf project deploy start --dry-run --source-dir force-app --target-org $ORG \
  --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/01-validacao.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "validacao" 01-validacao.txt

passo "2/6 Deploy"
sf project deploy start --source-dir force-app --target-org $ORG \
  --test-level RunSpecifiedTests $TL --wait 40 2>&1 | tee saida/02-deploy.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "deploy" 02-deploy.txt

passo "3/6 Permission set"
sf org assign permset --name EBL_RAIZ_Cockpit --target-org $ORG 2>&1 | tee saida/03-permset.txt
# ja atribuido nao e erro

passo "4/6 Carga de demonstracao"
sf apex run --file scripts/apex/seed-onda1.apex --target-org $ORG 2>&1 | tee saida/04-seed-bruto.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "carga" 04-seed-bruto.txt
grep -E "RAIZ|Compiled|Executed|ERROR" saida/04-seed-bruto.txt | grep -v "^.*|HEAP" > saida/04-seed.txt

passo "5/6 Agendamento do job diario"
sf apex run --file scripts/apex/agendar-onda1.apex --target-org $ORG 2>&1 | tee saida/05-agendar-bruto.txt
[ ${PIPESTATUS[0]} -eq 0 ] || falhou "agendamento" 05-agendar-bruto.txt
grep -E "RAIZ|Executed|ERROR" saida/05-agendar-bruto.txt > saida/05-agendar.txt
sleep 20

passo "6/6 Verificacao"
sf apex run --file scripts/apex/verificar-onda1.apex --target-org $ORG 2>&1 > saida/06-verificar-bruto.txt
grep -E "RAIZ |Executed|Error|EXCEPTION" saida/06-verificar-bruto.txt | sed 's/.*DEBUG|//' | tee saida/06-verificar.txt
sf apex run test --class-names RaizCockpitServiceTest --class-names RaizRiskEngineTest \
  --class-names RaizSimulationServiceTest --code-coverage --result-format human \
  --target-org $ORG --wait 20 2>&1 > saida/07-testes-cobertura.txt
grep -E "Outcome|Pass Rate|Tests Ran|Raiz|Habilitacao|Profissional" saida/07-testes-cobertura.txt | tee saida/07-resumo.txt

echo; echo "OK — terminou. Abra: sf org open --path lightning/n/Cockpit_RAIZ --target-org $ORG"
