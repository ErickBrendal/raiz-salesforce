# Publicar no GitHub

Feito pelo autor, na própria conta. Nada é publicado automaticamente.

1. Em github.com → **New repository**: nome `raiz-salesforce`, **Public**, sem README (o repositório já tem um).
2. No Terminal, dentro da pasta `raiz-salesforce`:
   ```
   git init -b main
   git add .
   git commit -m "RAIZ 1.0.0"
   git remote add origin https://github.com/ErickBrendal/raiz-salesforce.git
   git push -u origin main
   ```
3. No GitHub → **Releases** → **Draft a new release** → tag `v1.0.0` → título "RAIZ 1.0.0" → **Publish release**.
4. Na pasta `raiz-onda9`: `bash implantar-onda9.sh --github`. A integração lê a release e a liga ao deploy das Ondas 9–10.

Se o repositório foi criado **com** README, licença ou `.gitignore` pelo site, o `git push` será recusado. Nesse caso, antes do push: `git pull origin main --allow-unrelated-histories --no-rebase` e mantenha o README desta pasta se houver conflito.

Antes do passo 2, confira `git status`: não devem aparecer pastas `saida/`, `node_modules/` nem arquivos `.csv` de backup.
