import { LightningElement } from 'lwc';
import getPainel from '@salesforce/apex/RaizEngineeringService.getPainel';
import verificar from '@salesforce/apex/RaizEngineeringVerifier.verificar';
import getEstadoIntegracao from '@salesforce/apex/RaizGitHubService.getEstado';
import sincronizar from '@salesforce/apex/RaizGitHubService.sincronizar';

/**
 * RAIZ Engineering Intelligence (Onda 8) — status report executivo, funcional,
 * técnico, de arquitetura e de portfólio. Só leitura, exceto "Verificar agora",
 * que pede ao verificador Apex para conferir a org e gravar evidências.
 */
const DATA = new Intl.DateTimeFormat('pt-BR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'America/Sao_Paulo' });
export const VISOES = [
    { chave: 'executiva', rotulo: 'Executiva' },
    { chave: 'funcional', rotulo: 'Funcional' },
    { chave: 'tecnica', rotulo: 'Técnica' },
    { chave: 'arquitetura', rotulo: 'Arquitetura' },
    { chave: 'portfolio', rotulo: 'Portfólio' },
    { chave: 'automacao', rotulo: 'Automação' },
    { chave: 'integracao', rotulo: 'Integração' },
    { chave: 'implantacoes', rotulo: 'Implantações' }
];
const ESTADO = {
    Verificado: { rotulo: 'Verificado', cls: 'chip chip_ok' },
    Falhou: { rotulo: 'Falhou', cls: 'chip chip_ruim' },
    'Nao verificavel': { rotulo: 'Não verificável', cls: 'chip chip_aviso' },
    Declarado: { rotulo: 'Declarado', cls: 'chip' }
};

function fmt(d) {
    return d ? DATA.format(new Date(d)) : '—';
}

export default class RaizEngineeringIntelligence extends LightningElement {
    painel;
    carregando = true;
    erro;
    visao = 'executiva';
    ocupado = false;
    aviso;
    filtroTipo = '';

    connectedCallback() {
        this.carregar();
    }

    carregar() {
        this.carregando = true;
        return getPainel()
            .then((p) => {
                this.painel = p;
                this.erro = p.erro;
            })
            .catch((e) => {
                this.erro = (e && e.body && e.body.message) || 'Erro ao carregar o painel.';
            })
            .finally(() => {
                this.carregando = false;
            });
    }

    verificarAgora() {
        this.ocupado = true;
        this.aviso = undefined;
        verificar()
            .then((r) => {
                this.aviso = 'Verificação concluída: ' + r.verificados + ' verificados, ' + r.falhas + ' com falha, ' +
                    r.naoVerificaveis + ' não verificáveis, ' + r.planejados + ' planejados.';
                return this.carregar();
            })
            .catch((e) => {
                this.aviso = (e && e.body && e.body.message) || 'Verificação não concluída.';
            })
            .finally(() => {
                this.ocupado = false;
            });
    }

    // ------------------------------------------------------------ estado
    get pronto() {
        return !this.carregando && !!this.painel && !this.erro;
    }
    get abas() {
        return VISOES.map((v) => ({ ...v, cls: 'aba' + (v.chave === this.visao ? ' aba_ativa' : ''), atual: v.chave === this.visao ? 'page' : 'false' }));
    }
    trocarVisao(e) {
        this.visao = e.currentTarget.dataset.chave;
        if (this.visao === 'integracao' && !this.integracao) this.carregarIntegracao();
    }
    integracao;
    avisoIntegracao;
    carregarIntegracao() {
        return getEstadoIntegracao()
            .then((e) => {
                this.integracao = e;
            })
            .catch((e) => {
                this.integracao = { erro: (e && e.body && e.body.message) || 'Integração indisponível.', releases: [], execucoes: [] };
            });
    }
    sincronizarAgora() {
        this.ocupado = true;
        this.avisoIntegracao = undefined;
        sincronizar()
            .then((r) => {
                this.avisoIntegracao = r.status + ': ' + r.mensagem;
                return this.carregarIntegracao();
            })
            .catch((e) => {
                this.avisoIntegracao = (e && e.body && e.body.message) || 'Sincronização não concluída.';
            })
            .finally(() => {
                this.ocupado = false;
            });
    }
    get erroIntegracao() {
        return this.integracao ? this.integracao.erro : undefined;
    }
    get vIntegracao() { return this.visao === 'integracao'; }
    get cfg() {
        return (this.integracao && this.integracao.config) || {};
    }
    get repoTexto() {
        const c = this.cfg;
        return c.owner ? c.owner + '/' + c.repositorio + (c.demonstracao ? ' (repositório de demonstração)' : '') : 'sem configuração';
    }
    get releases() {
        return (this.integracao ? this.integracao.releases : []).map((r) => ({
            ...r,
            publicadaFmt: fmt(r.publicadaEm),
            implTxt: r.implantada ? 'Sim (' + r.implantacoes + ')' : 'Não',
            implCls: 'chip' + (r.implantada ? ' chip_ok' : '')
        }));
    }
    get semReleases() {
        return this.releases.length === 0;
    }
    get execucoesIntegracao() {
        return (this.integracao ? this.integracao.execucoes : []).map((x, i) => ({
            ...x,
            k: 'ex' + i,
            quandoFmt: fmt(x.quando),
            cls: 'chip' + (x.status === 'Sucesso' ? ' chip_ok' : x.status === 'Erro' ? ' chip_ruim' : ' chip_aviso')
        }));
    }
    get vExecutiva() { return this.visao === 'executiva'; }
    get vFuncional() { return this.visao === 'funcional'; }
    get vTecnica() { return this.visao === 'tecnica'; }
    get vArquitetura() { return this.visao === 'arquitetura'; }
    get vPortfolio() { return this.visao === 'portfolio'; }
    get vAutomacao() { return this.visao === 'automacao'; }
    get vImplantacoes() { return this.visao === 'implantacoes'; }

    get carimbo() {
        if (!this.painel || !this.painel.ultimaVerificacao) return 'Ainda não verificado na org. Clique em "Verificar agora".';
        return 'Última verificação: ' + fmt(this.painel.ultimaVerificacao) + ' · origem: ' + (this.painel.origemVerificacao || '—');
    }

    get indicadores() {
        return (this.painel ? this.painel.indicadores : []).map((i) => ({ ...i, cls: 'kpi kpi_' + i.tom }));
    }
    get pendencias() {
        return (this.painel ? this.painel.pendencias : []).map((t, n) => ({ k: 'pd' + n, t }));
    }
    get temPendencias() {
        return this.pendencias.length > 0;
    }

    deco(i) {
        const e = ESTADO[i.estado] || ESTADO.Declarado;
        return { ...i, estadoRotulo: e.rotulo, estadoCls: e.cls, quandoFmt: fmt(i.verificadoEm) };
    }
    get funcionalidades() {
        return (this.painel ? this.painel.funcionalidades : []).map((f) => ({
            ...this.deco(f),
            cobertura: f.componentes ? f.componentesVerificados + ' de ' + f.componentes + ' componentes verificados' : 'sem componentes ligados'
        }));
    }
    get tipos() {
        const s = new Set((this.painel ? this.painel.componentes : []).map((c) => c.tipo));
        return [{ label: 'Todos os tipos', value: '' }, ...[...s].sort().map((t) => ({ label: t, value: t }))];
    }
    mudarTipo(e) {
        this.filtroTipo = e.detail.value;
    }
    get componentes() {
        return (this.painel ? this.painel.componentes : [])
            .filter((c) => !this.filtroTipo || c.tipo === this.filtroTipo)
            .map((c) => this.deco(c));
    }
    get modulos() {
        const m = new Map();
        (this.painel ? this.painel.componentes : []).forEach((c) => {
            if (!m.has(c.modulo)) m.set(c.modulo, { nome: c.modulo, itens: [], adrs: new Set(), ver: 0 });
            const g = m.get(c.modulo);
            g.itens.push(this.deco(c));
            if (c.adr) c.adr.split(/[,;]\s*/).forEach((a) => g.adrs.add(a));
            if (c.estado === 'Verificado') g.ver++;
        });
        return [...m.values()].map((g) => ({
            nome: g.nome,
            itens: g.itens,
            resumo: g.ver + ' de ' + g.itens.length + ' verificados',
            adrs: [...g.adrs].sort().join(' · ') || '—'
        }));
    }
    get portfolio() {
        return (this.painel ? this.painel.funcionalidades : []).filter((f) => f.portfolio).map((f) => this.deco(f));
    }
    get logs() {
        return (this.painel ? this.painel.logs : []).map((l) => ({
            ...l,
            quandoFmt: fmt(l.quando),
            cls: 'chip' + (l.status === 'Sucesso' ? ' chip_ok' : l.status === 'Erro' ? ' chip_ruim' : l.status === 'Bloqueado' ? ' chip_aviso' : '')
        }));
    }
    get implantacoes() {
        return (this.painel ? this.painel.implantacoes : []).map((d) => ({
            ...d,
            quandoFmt: fmt(d.quando),
            testesTxt: d.testes == null ? '—' : d.aprovados + '/' + d.testes,
            cls: 'chip' + (d.resultado === 'Sucesso' ? ' chip_ok' : ' chip_ruim')
        }));
    }
    get semImplantacoes() {
        return this.implantacoes.length === 0;
    }
}
