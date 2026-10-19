#!/bin/bash
# RAIZ 4.0 — Fase 0: auditoria SOMENTE LEITURA da org.
# Nao cria, altera nem apaga nada. Nao imprime token nem senha.
# Uso: cd ~/Downloads/raiz4 && bash auditar-raiz4.sh
set -u
ORG=${1:-radar}
cd "$(dirname "$0")"; mkdir -p saida
S=saida
q()  { echo "-- $1" >> $S/erros.txt; sf data query --target-org $ORG --result-format csv --query "$2" > "$S/$1.csv" 2>>$S/erros.txt || echo "FALHOU: $1" | tee -a $S/erros.txt; }
qt() { echo "-- $1" >> $S/erros.txt; sf data query --use-tooling-api --target-org $ORG --result-format csv --query "$2" > "$S/$1.csv" 2>>$S/erros.txt || echo "FALHOU: $1" | tee -a $S/erros.txt; }
: > $S/erros.txt
echo "==== 1/6 Org"
q  org "SELECT Name, OrganizationType, IsSandbox, InstanceName FROM Organization"
echo "==== 2/6 Objetos, campos e regras"
qt objetos "SELECT DeveloperName, NamespacePrefix FROM CustomObject ORDER BY DeveloperName"
for o in Business_Rule__c CRM_Kanban_Task__c Task_Stage_Log__c Project__c Processo_Critico__c Task; do
  sf sobject describe --sobject $o --target-org $ORG --json > "$S/describe-$o.json" 2>>$S/erros.txt || echo "FALHOU: describe $o" | tee -a $S/erros.txt
done
qt regras-validacao "SELECT ValidationName, EntityDefinition.QualifiedApiName, Active FROM ValidationRule ORDER BY EntityDefinition.QualifiedApiName"
echo "==== 3/6 Codigo e automacoes"
q  apex-classes "SELECT Name, ApiVersion, LengthWithoutComments, LastModifiedDate FROM ApexClass WHERE NamespacePrefix = null ORDER BY Name"
q  apex-triggers "SELECT Name, TableEnumOrId, Status FROM ApexTrigger WHERE NamespacePrefix = null ORDER BY Name"
qt lwc "SELECT DeveloperName, MasterLabel, LastModifiedDate FROM LightningComponentBundle WHERE NamespacePrefix = null ORDER BY DeveloperName"
q  flows "SELECT ApiName, Label, ProcessType, TriggerType, IsActive, LastModifiedDate FROM FlowDefinitionView ORDER BY ApiName"
q  jobs-agendados "SELECT CronJobDetail.Name, State, NextFireTime, CronExpression FROM CronTrigger"
for t in CustomTab FlexiPage CustomApplication PermissionSet CustomPermission CustomMetadata StaticResource NamedCredential ExternalCredential RemoteSiteSetting CustomNotificationType; do
  sf org list metadata --metadata-type $t --target-org $ORG --json > "$S/meta-$t.json" 2>>$S/erros.txt || echo "FALHOU: meta $t" | tee -a $S/erros.txt
done
echo "==== 4/6 Testes e cobertura (ultima execucao registrada)"
q  testes-execucoes "SELECT AsyncApexJobId, StartTime, EndTime, Status, MethodsEnqueued, MethodsCompleted, MethodsFailed FROM ApexTestRunResult ORDER BY StartTime DESC LIMIT 10"
q  testes-resultados "SELECT ApexClass.Name, MethodName, Outcome, TestTimestamp FROM ApexTestResult ORDER BY TestTimestamp DESC LIMIT 400"
qt cobertura "SELECT ApexClassOrTrigger.Name, NumLinesCovered, NumLinesUncovered FROM ApexCodeCoverageAggregate"
echo "==== 5/6 Dados (somente contagens)"
q  docs-por-status "SELECT Status__c, COUNT(Id) total FROM Business_Rule__c GROUP BY Status__c"
q  docs-sem-processo "SELECT COUNT(Id) total FROM Business_Rule__c WHERE Processo_Critico__c = null"
q  kanban-por-coluna "SELECT CRM_Kanban_Stage__c, COUNT(Id) total FROM CRM_Kanban_Task__c GROUP BY CRM_Kanban_Stage__c"
q  kanban-com-documento "SELECT COUNT(Id) total FROM CRM_Kanban_Task__c WHERE Business_Rule__c != null"
q  projetos "SELECT Name, Status__c FROM Project__c ORDER BY Name"
q  tarefas-padrao "SELECT COUNT(Id) total FROM Task"
q  permsets-raiz "SELECT PermissionSet.Name, COUNT(Id) total FROM PermissionSetAssignment WHERE PermissionSet.Name LIKE '%RAIZ%' GROUP BY PermissionSet.Name"
echo "==== 6/6 Ferramentas locais"
{ sf --version; command -v jq || echo "jq: ausente"; command -v python3 || echo "python3: ausente"; } > $S/ferramentas.txt 2>&1
echo "==== Fim"
ls -1 $S | wc -l | xargs echo "arquivos gerados:"
grep -c FALHOU $S/erros.txt | xargs echo "consultas com falha:"
echo "OK — nada foi alterado na org. Me avise que terminou; eu leio a pasta saida."
