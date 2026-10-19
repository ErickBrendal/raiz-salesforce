# Demonstração guiada · 10 minutos (RAIZ 4.0)

O mesmo roteiro está dentro da org, na aba **Portfolio Demo Mode**, com visão funcional e técnica, pergunta provável e limitação de cada etapa. **Dados fictícios.** Os números não estão no roteiro de propósito: leia-os na tela na hora.

| Min | Etapa | Onde | O que mostrar | Frase-chave |
|---|---|---|---|---|
| 0–1 | O problema | Cockpit RAIZ | Os 5 indicadores com "Todos os clientes" | "Nenhum número aqui é digitado: tudo vem de registro." |
| 1–2 | Quatro estados | Cockpit → Estado da cobertura e Concentração | Ponto único × coberto × sem informação; quem está sozinho em mais processos | "Sem dado nunca vira verde." |
| 2–3,5 | Simulador | Cockpit → Simulador de ausência → Fabio Teixeira | O que para, o que fica frágil, quem cobre, exposição e horas | "É somente leitura: simulação não é fato." |
| 3,5–4,5 | Mitigação | Cockpit → Planos de mitigação | Plano atrasado e ações | "Concluir o plano não marca ninguém como apto." |
| 4,5–6 | Cadastro guiado | Aba Cadastro guiado RAIZ | Avançar até a tela 6 sem salvar; tentar um processo já publicado | "Nada é gravado antes da última tela, e não duplica." |
| 6–7,5 | Governança | Knowledge Hub → "Em revisão"; aba Logs de execução | Documento A "Em revisão com Revisor Demo"; B "Bloqueado: falta …"; coluna Execuções | "Rodar de novo não duplica; incompleto não vira tarefa." |
| 7,5–8,5 | Engenharia | Engineering Intelligence → Verificar agora | Regras ao lado de cada número; visão Implantações | "Preencher não valida: só o verificador marca Verificado." |
| 8,5–9 | Integração | Engineering Intelligence → Integração | Releases e "Implantada na org?" | "Release publicada não é deploy." |
| 9–10 | Engineering with AI | Portfolio Demo Mode, rodapé | O que o autor decidiu × o que a IA fez | "A prova é a decisão, o teste e a evidência — não o código gerado." |

## Antes de apresentar

1. Rode `bash scripts/implantacao/implantar-onda8.sh --evidencias` (evidências de LWC valem 7 dias).
2. Abra cada aba uma vez para aquecer o cache da página.
3. Confira se o documento C já mostra "Revisão atrasada" (o caminho agendado roda um dia após o prazo).

## Se algo der errado ao vivo

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Aviso "Sem acesso" | Usuário sem permission set | Atribuir `EBL_RAIZ_Cockpit` (e `RAIZ_Aprovador` para aprovar) |
| Revisor não aparece no cadastro | Ninguém além do autor tem a permissão de aprovação | Usar o Revisor Demo |
| Sincronização do GitHub com 403 | Limite anônimo do GitHub (IPs compartilhados) | Mostrar o log com o código HTTP: é o comportamento esperado |
| Itens "Não verificável" | Evidência do sf CLI com mais de 7 dias | Rodar a atualização de evidências |
