import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getPainel from '@salesforce/apex/RaizMitigationService.getPainel';
import criarPlano from '@salesforce/apex/RaizMitigationService.criarPlano';
import concluirAcao from '@salesforce/apex/RaizMitigationService.concluirAcao';
import mudarStatusPlano from '@salesforce/apex/RaizMitigationService.mudarStatusPlano';

const BRL = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const DATA = new Intl.DateTimeFormat('pt-BR', { timeZone: 'UTC' });

/**
 * Planos de mitigacao (Metodo RAIZ, Onda 3).
 * Leitura por wire; toda escrita e um clique explicito do usuario
 * (criar plano pede confirmacao). Numeros vem do Apex.
 */
export default class RaizPlanosMitigacao extends LightningElement {
    clientes = [];
    contaId = '';
    painel;
    erro;
    erroAcao;
    carregando = true;
    ocupado = false;
    confirmando = null; // processoId aguardando confirmacao
    respostaWire;

    @wire(getClientes)
    wiredClientes({ data, error }) {
        if (data) this.clientes = data.map((c) => ({ label: c.label, value: c.value }));
        if (error) this.erroAcao = 'Lista de clientes indisponível: ' + this.mensagem(error);
    }

    @wire(getPainel, { contaId: '$contaParam' })
    wiredPainel(resposta) {
        this.respostaWire = resposta;
        const { data, error } = resposta;
        if (data) {
            this.painel = data;
            this.erro = undefined;
            this.carregando = false;
        } else if (error) {
            this.painel = undefined;
            this.erro = this.mensagem(error);
            this.carregando = false;
        }
    }

    get contaParam() {
        return this.contaId ? this.contaId : null;
    }

    mensagem(e) {
        if (!e) return 'Erro desconhecido.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return 'Erro desconhecido.';
    }

    // ------------------------------------------------------------ estados
    get semPermissao() {
        return !!this.erro && this.erro.indexOf('SEM_PERMISSAO') === 0;
    }
    get textoPermissao() {
        return this.erro ? this.erro.replace('SEM_PERMISSAO: ', '') : '';
    }
    get erroGeral() {
        return !!this.erro && !this.semPermissao;
    }
    get pronto() {
        return !this.carregando && !this.erro && !!this.painel;
    }
    get temSugestoes() {
        return this.pronto && this.painel.sugestoes.length > 0;
    }
    get temPlanos() {
        return this.pronto && this.painel.planos.length > 0;
    }
    get nadaAFazer() {
        return this.pronto && !this.temSugestoes && !this.temPlanos;
    }
    get resumoAcoes() {
        return this.painel ? this.painel.acoesConcluidas + ' / ' + this.painel.acoesTotal : '';
    }
    get maisSugestoes() {
        if (!this.pronto) return '';
        const resto = this.painel.processosSemPlano - this.painel.sugestoes.length;
        return resto > 0 ? '+ ' + resto + (resto === 1 ? ' processo' : ' processos') + ' sem plano fora desta lista.' : '';
    }

    // ------------------------------------------------------- apresentacao
    get sugestoes() {
        if (!this.temSugestoes) return [];
        return this.painel.sugestoes.map((s) => ({
            ...s,
            exposicaoFmt: s.exposicao ? BRL.format(s.exposicao) : '—',
            confirmar: this.confirmando === s.processoId,
            classeFarol: 'farol farol_' + String(s.farol || 'Baixo').toLowerCase()
        }));
    }
    get planos() {
        if (!this.temPlanos) return [];
        return this.painel.planos.map((p) => ({
            ...p,
            alvoFmt: p.dataAlvo ? DATA.format(new Date(p.dataAlvo)) : 'sem data',
            barra: 'width:' + p.progresso + '%',
            classeStatus: 'chip' + (p.atrasado ? ' chip_atraso' : ''),
            rascunho: p.status === 'Rascunho',
            reducao:
                p.scoreInicial != null && p.scoreAtual != null
                    ? 'Score ' + p.scoreInicial + ' → ' + p.scoreAtual
                    : '',
            acoes: p.acoes.map((a) => ({
                ...a,
                prazoFmt: a.prazo ? DATA.format(new Date(a.prazo)) : '',
                classe: 'acao' + (a.concluida ? ' acao_feita' : '') + (a.atrasada ? ' acao_atraso' : '')
            }))
        }));
    }
    get premissas() {
        return (this.painel ? this.painel.premissas : []).map((t, i) => ({ id: 'pm' + i, texto: t }));
    }

    // ------------------------------------------------------------ eventos
    mudarCliente(evt) {
        this.contaId = evt.detail.value;
        this.carregando = true;
        this.confirmando = null;
    }

    pedirConfirmacao(evt) {
        this.confirmando = evt.currentTarget.dataset.id;
        this.erroAcao = undefined;
    }
    cancelarConfirmacao() {
        this.confirmando = null;
    }
    async confirmarCriacao(evt) {
        await this.executar(() => criarPlano({ processoId: evt.currentTarget.dataset.id }));
        this.confirmando = null;
    }
    async concluir(evt) {
        await this.executar(() => concluirAcao({ acaoId: evt.currentTarget.dataset.id }));
    }
    async iniciar(evt) {
        await this.executar(() => mudarStatusPlano({ planoId: evt.currentTarget.dataset.id, status: 'Em execucao' }));
    }
    async finalizar(evt) {
        await this.executar(() => mudarStatusPlano({ planoId: evt.currentTarget.dataset.id, status: 'Concluido' }));
    }

    async executar(fn) {
        this.ocupado = true;
        this.erroAcao = undefined;
        try {
            await fn();
            await refreshApex(this.respostaWire);
        } catch (e) {
            this.erroAcao = this.mensagem(e);
        } finally {
            this.ocupado = false;
        }
    }
}
