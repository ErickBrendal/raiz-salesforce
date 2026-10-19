# Trilhas por perfil

Cada trilha termina num exercício. O objetivo é entender a implementação a ponto de mudar algo com segurança — não decorar respostas.

| Perfil | Duração | Passos | Exercício de saída |
|---|---|---|---|
| Gestor de negócio | 30 min | 1. [Demonstração guiada](../DEMO-GUIADA.md) · 2. Fichas de cobertura, simulador e governança · 3. ADRs 003 e 008 | Explicar a um diretor por que "plano concluído" não reduz risco e o que é ponto único |
| CRM Technology Lead | 1 h | 1. Trilha do gestor · 2. [Arquitetura](../ARQUITETURA.md) (permissões e segurança) · 3. ADRs 005, 006, 018 · 4. Atribuir `RAIZ_Leitor` a um usuário e navegar | Defender, para um time de TI, o reaproveitamento do Documento Funcional e o uso de `without sharing` só na automação |
| Senior Salesforce Developer | 2 h | 1. Ler `RaizJourneyService` e o teste · 2. Ler `RaizGovernancaAction` e `RaizLog` · 3. Ler `RaizGitHubService` e os mocks · 4. Rodar Jest e os testes Apex | Mudar a regra de submissão (ex.: exigir prazo) e ver quais testes quebram, em Apex e no Jest |
| Salesforce Technical Lead | 2 h | 1. Trilha do developer · 2. Scripts em `scripts/implantacao` (dry-run, testes especificados, cargas idempotentes) · 3. ADRs 009, 013, 015 | Planejar a próxima onda: o que validar antes, como reverter, como provar que entrou |
| Salesforce Solution Architect | 3 h | 1. Todas as ADRs · 2. [Blueprint 4.0](../BLUEPRINT-RAIZ-4.md) · 3. [Roadmap](../ROADMAP.md) · 4. Dependência do Kanban no README | Redesenhar a integração com o Kanban para o RAIZ instalar em qualquer org (interface + implementação opcional) |
