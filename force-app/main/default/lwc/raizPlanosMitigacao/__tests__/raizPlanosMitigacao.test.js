import { createElement } from 'lwc';
import RaizPlanosMitigacao from 'c/raizPlanosMitigacao';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';
import getPainel from '@salesforce/apex/RaizMitigationService.getPainel';
import criarPlano from '@salesforce/apex/RaizMitigationService.criarPlano';
import concluirAcao from '@salesforce/apex/RaizMitigationService.concluirAcao';
import mudarStatusPlano from '@salesforce/apex/RaizMitigationService.mudarStatusPlano';

jest.mock('@salesforce/apex/RaizCockpitService.getClientes', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizMitigationService.getPainel', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizMitigationService.criarPlano', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizMitigationService.concluirAcao', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizMitigationService.mudarStatusPlano', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), { virtual: true });

const PAINEL = {
    planosAbertos: 1, planosAtrasados: 1, acoesTotal: 3, acoesConcluidas: 1, processosSemPlano: 12,
    premissas: ['Concluir o plano não marca ninguém como apto.'],
    sugestoes: [{ processoId: 'p1', processo: 'Roteiro de produção', conta: 'Aurora', estado: 'Ponto unico', score: 24,
        farol: 'Critico', exposicao: 313600, objetivo: 'Habilitar substituto', objetivoRotulo: 'Habilitar substituto',
        motivo: 'Só uma pessoa apta.' }],
    planos: [{ id: 'pl1', processo: 'Política de desconto', objetivoRotulo: 'Habilitar substituto', status: 'Rascunho',
        statusRotulo: 'Rascunho', atrasado: true, dataAlvo: '2026-11-16', responsavel: 'Helena Prado', acoesTotal: 3,
        acoesConcluidas: 3, progresso: 100, scoreInicial: 12, scoreAtual: 6, podeConcluir: true,
        acoes: [{ id: 'a1', descricao: 'Definir substituto', statusRotulo: 'Concluída', concluida: true, atrasada: false, prazo: '2026-10-24' },
                { id: 'a2', descricao: 'Execução acompanhada', statusRotulo: 'A fazer', concluida: false, atrasada: true, prazo: '2026-10-10' }] }]
};

const flush = () => new Promise((r) => setTimeout(r, 0));
function montar() {
    const el = createElement('c-raiz-planos-mitigacao', { is: RaizPlanosMitigacao });
    document.body.appendChild(el);
    return el;
}
const q = (el, sel) => el.shadowRoot.querySelector(sel);

describe('c-raiz-planos-mitigacao', () => {
    afterEach(() => {
        while (document.body.firstChild) document.body.removeChild(document.body.firstChild);
        jest.clearAllMocks();
    });

    it('carrega sem inventar numero e depois mostra o painel', async () => {
        const el = montar();
        expect(q(el, '[data-id="carregando"]')).not.toBeNull();
        getClientes.emit([{ label: 'Todos', value: '' }]);
        getPainel.emit(PAINEL);
        await flush();
        expect(q(el, '[data-id="abertos"]').textContent).toBe('1');
        expect(q(el, '[data-id="acoes"]').textContent).toBe('1 / 3');
        expect(q(el, '[data-id="sugestoes"]').textContent.replace(/\s/g, ' ')).toContain('R$ 313.600');
        expect(q(el, '.plano').textContent).toContain('Score 12 → 6');
        expect(q(el, '.plano').textContent).toContain('atrasado');
        expect(q(el, '.nota').textContent).toContain('11 processos');
    });

    it('criar plano exige confirmacao e recarrega', async () => {
        criarPlano.mockResolvedValue('pl2');
        const el = montar();
        getPainel.emit(PAINEL);
        await flush();
        q(el, 'button[data-acao="criar"]').click();
        await flush();
        expect(criarPlano).not.toHaveBeenCalled();
        q(el, 'button[data-acao="confirmar"]').click();
        await flush();
        expect(criarPlano).toHaveBeenCalledWith({ processoId: 'p1' });
    });

    it('cancelar confirmacao nao cria', async () => {
        const el = montar();
        getPainel.emit(PAINEL);
        await flush();
        q(el, 'button[data-acao="criar"]').click();
        await flush();
        q(el, 'button[data-acao="cancelar"]').click();
        await flush();
        expect(q(el, 'button[data-acao="confirmar"]')).toBeNull();
        expect(criarPlano).not.toHaveBeenCalled();
    });

    it('concluir acao, iniciar e concluir plano chamam o Apex; erro aparece', async () => {
        concluirAcao.mockResolvedValue();
        mudarStatusPlano.mockResolvedValue();
        const el = montar();
        getPainel.emit(PAINEL);
        await flush();
        q(el, 'button[data-acao="concluir"]').click();
        await flush();
        expect(concluirAcao).toHaveBeenCalledWith({ acaoId: 'a2' });
        q(el, 'button[data-acao="iniciar"]').click();
        await flush();
        expect(mudarStatusPlano).toHaveBeenCalledWith({ planoId: 'pl1', status: 'Em execucao' });
        mudarStatusPlano.mockRejectedValue({ body: { message: 'Conclua todas as ações antes de concluir o plano.' } });
        q(el, 'button[data-acao="finalizar"]').click();
        await flush();
        expect(q(el, '[data-id="erro-acao"]').textContent).toContain('Conclua todas');
    });

    it('vazio, sem permissao e erro tem estados proprios', async () => {
        let el = montar();
        getPainel.emit({ ...PAINEL, sugestoes: [], planos: [], processosSemPlano: 0 });
        await flush();
        expect(q(el, '[data-id="vazio"]')).not.toBeNull();
        document.body.removeChild(el);

        el = montar();
        getPainel.error({ message: 'SEM_PERMISSAO: peça o permission set EBL_RAIZ_Cockpit.' });
        await flush();
        expect(q(el, '[data-id="sem-permissao"]').textContent).toContain('EBL_RAIZ_Cockpit');
        document.body.removeChild(el);

        el = montar();
        getPainel.error({ message: 'falhou' });
        await flush();
        expect(q(el, '[data-id="erro"]').textContent).toContain('falhou');
        q(el, '[data-id="cliente"]').dispatchEvent(new CustomEvent('change', { detail: { value: 'c1' } }));
        await flush();
        expect(getPainel.getLastConfig()).toEqual({ contaId: 'c1' });
    });
});
