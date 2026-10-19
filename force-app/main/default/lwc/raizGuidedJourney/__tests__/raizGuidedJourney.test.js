import { createElement } from 'lwc';
import RaizGuidedJourney from 'c/raizGuidedJourney';
import getContexto from '@salesforce/apex/RaizJourneyService.getContexto';
import getSituacao from '@salesforce/apex/RaizJourneyService.getSituacao';
import validar from '@salesforce/apex/RaizJourneyService.validar';
import salvar from '@salesforce/apex/RaizJourneyService.salvar';

jest.mock('@salesforce/apex/RaizJourneyService.getContexto', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizJourneyService.getSituacao', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizJourneyService.validar', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizJourneyService.salvar', () => ({ default: jest.fn() }), { virtual: true });

const CTX = {
    usuarioId: 'u1',
    usuarioNome: 'Autor Demo',
    processos: [
        { id: 'p1', nome: 'Apuração de impostos', area: 'Fiscal', responsavel: 'Dona', criticidade: 'Crítico', criticidadeDocumento: 'Critica', estadoCobertura: 'Ponto unico', situacaoDocumento: 'Sem documento' },
        { id: 'p2', nome: 'Faturamento', area: 'Fiscal', responsavel: 'Dona', criticidade: 'Alto', criticidadeDocumento: 'Alta', estadoCobertura: 'Coberto', situacaoDocumento: 'Publicada' }
    ],
    tipos: [{ label: 'Procedimento operacional', value: 'Procedimento operacional' }],
    categorias: [{ label: 'Fiscal', value: 'Fiscal' }],
    criticidades: [{ label: 'Crítica', value: 'Critica' }],
    revisores: [{ id: 'u2', nome: 'Revisor Demo' }]
};
const SEM_BLOQUEIO = { bloqueios: [], avisos: [] };
const flush = () => new Promise((r) => setTimeout(r, 0));
const montar = () => {
    const el = createElement('c-raiz-guided-journey', { is: RaizGuidedJourney });
    document.body.appendChild(el);
    return el;
};
const botao = (el, label) => [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === label);
const clicar = (el, label) => botao(el, label).dispatchEvent(new CustomEvent('click'));
const texto = (el) => el.shadowRoot.textContent;

async function ateProcesso(el, situacao) {
    getSituacao.mockResolvedValue(situacao);
    await flush();
    clicar(el, 'Começar');
    await flush();
    const cb = el.shadowRoot.querySelector('lightning-combobox');
    cb.dispatchEvent(new CustomEvent('change', { detail: { value: situacao.processoId || 'p1' } }));
    await flush();
}

describe('c-raiz-guided-journey', () => {
    beforeEach(() => {
        getContexto.mockResolvedValue(CTX);
        validar.mockResolvedValue(SEM_BLOQUEIO);
    });
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('abre nas boas-vindas com 7 etapas e nada gravado', async () => {
        const el = montar();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.trilha button').length).toBe(7);
        expect(texto(el)).toContain('Vamos registrar o conhecimento necessário');
        expect(texto(el)).toContain('Nada é gravado até a última tela');
        expect(salvar).not.toHaveBeenCalled();
    });

    it('mostra o contexto do processo e preenche titulo e criticidade', async () => {
        const el = montar();
        await ateProcesso(el, { estado: 'NOVO', podeContinuar: true, mensagem: 'Primeiro documento.', dados: null });
        expect(getSituacao).toHaveBeenCalledWith({ processoId: 'p1' });
        expect(texto(el)).toContain('Ponto único de falha');
        expect(texto(el)).toContain('Primeiro documento.');
        expect(botao(el, 'Próximo').disabled).toBe(false);
        clicar(el, 'Próximo');
        await flush();
        await flush();
        const payload = JSON.parse(validar.mock.calls[0][0].dadosJson);
        expect(payload.titulo).toBe('Registro — Apuração de impostos');
        expect(payload.criticidade).toBe('Critica');
        expect(texto(el)).toContain('Classifique o documento');
    });

    it('bloqueia processo ja publicado e oferece o Knowledge Hub', async () => {
        const el = montar();
        await ateProcesso(el, { estado: 'PUBLICADO', podeContinuar: false, mensagem: 'O documento deste processo já está publicado.', dados: { documentoId: 'd1' } });
        expect(texto(el)).toContain('já está publicado');
        expect(botao(el, 'Abrir Knowledge Hub')).toBeTruthy();
        expect(botao(el, 'Próximo').disabled).toBe(true);
    });

    it('mostra so os bloqueios da etapa atual e nao avanca', async () => {
        const el = montar();
        await ateProcesso(el, { estado: 'NOVO', podeContinuar: true, mensagem: 'ok', dados: null });
        clicar(el, 'Próximo');
        await flush();
        validar.mockResolvedValueOnce({ bloqueios: [{ etapa: 3, mensagem: 'Escolha o tipo de documento.' }, { etapa: 4, mensagem: 'Escolha a criticidade.' }], avisos: [] });
        clicar(el, 'Próximo');
        await flush();
        expect(texto(el)).toContain('Escolha o tipo de documento.');
        expect(texto(el)).not.toContain('Escolha a criticidade.');
        expect(texto(el)).toContain('Classifique o documento');
    });

    it('salva e encaminha so na tela 7 e mostra o resultado com avisos', async () => {
        salvar.mockResolvedValue({
            documentoId: 'd9', status: 'Em Analise', criado: true, encaminhado: true,
            cartao: { id: 'k1', etapa: 'Em atendimento-Analise TI', acao: 'criado' },
            avisos: ['Sem prazo de revisão: o documento não terá acompanhamento de vencimento.'],
            proximosPassos: ['O revisor avalia o documento no Knowledge Hub.']
        });
        const el = montar();
        await ateProcesso(el, { estado: 'NOVO', podeContinuar: true, mensagem: 'ok', dados: null });
        for (let i = 0; i < 4; i++) {
            clicar(el, 'Próximo');
            await flush();
            await flush();
        }
        expect(texto(el)).toContain('Confira antes de salvar');
        expect(salvar).not.toHaveBeenCalled();
        clicar(el, 'Ir para a confirmação');
        await flush();
        clicar(el, 'Salvar e encaminhar para revisão');
        await flush();
        expect(salvar.mock.calls[0][0].encaminhar).toBe(true);
        expect(texto(el)).toContain('Encaminhado para revisão');
        expect(texto(el)).toContain('Documento criado');
        expect(texto(el)).toContain('Cartão do Kanban criado na coluna "Em atendimento-Analise TI"');
        expect(texto(el)).toContain('Sem prazo de revisão');
    });

    it('erro ao salvar mantem os dados e explica', async () => {
        salvar.mockRejectedValue({ body: { message: 'Não foi possível concluir: falha simulada' } });
        const el = montar();
        await ateProcesso(el, { estado: 'NOVO', podeContinuar: true, mensagem: 'ok', dados: null });
        for (let i = 0; i < 5; i++) {
            clicar(el, i === 4 ? 'Ir para a confirmação' : 'Próximo');
            await flush();
            await flush();
        }
        clicar(el, 'Salvar rascunho');
        await flush();
        expect(salvar.mock.calls[0][0].encaminhar).toBe(false);
        expect(texto(el)).toContain('Não foi salvo.');
        expect(texto(el)).toContain('Os dados continuam aqui');
        expect(botao(el, 'Salvar rascunho')).toBeTruthy();
    });

    it('sem permissao mostra mensagem em vez de tela vazia', async () => {
        getContexto.mockRejectedValue({ body: { message: 'SEM_PERMISSAO: peça o permission set EBL_RAIZ_Cockpit.' } });
        const el = montar();
        await flush();
        expect(texto(el)).toContain('Acesso necessário.');
        expect(texto(el)).toContain('EBL_RAIZ_Cockpit');
        expect(el.shadowRoot.querySelector('.trilha')).toBeNull();
    });
});
