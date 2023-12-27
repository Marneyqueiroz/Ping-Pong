create
or replace PROCEDURE "GA_STP_PROCESSARPLANILHA" (
    P_CODUSU NUMBER,
    -- Código do usuário logado
    P_IDSESSAO VARCHAR2,
    -- Identificador da execução. Serve para buscar informações dos parâmetros/campos da execução.
    P_QTDLINHAS NUMBER,
    -- Informa a quantidade de registros selecionados no momento da execução.
    P_MENSAGEM OUT VARCHAR2 -- Caso seja passada uma mensagem aqui, ela será exibida como uma informação ao usuário.
) AS FIELD_NUNICO NUMBER;

V_VLRTOTABAIXA FLOAT;

V_VLRUNITAEM FLOAT;

V_VLRARECITEM FLOAT;

V_VLRDEVIDO FLOAT;

V_TOTREPASSECALC FLOAT;

V_REMUNERACAO FLOAT;

V_VLRTOTALREPASSE FLOAT;

V_VLRUNITCLI FLOAT;

V_NUNOTA NUMBER;

V_DHTIPOPER TIMESTAMP;

V_DHTIPOPERFIN TIMESTAMP;

V_NEWNUBCO NUMBER;

V_NEWNUFIN NUMBER;

V_NEWVLRDESDOB FLOAT;

V_NEWNUACERTO NUMBER;

V_CODPARC NUMBER;

V_CODEMP NUMBER;

V_PROCESSOU VARCHAR2(10);

V_NUFIN NUMBER;

V_VLRLIQ DECIMAL;

V_VLRDESC DECIMAL;

V_HISTORICOVNDACONTADA VARCHAR(4000);

BEGIN V_VLRTOTABAIXA := 0;

V_REMUNERACAO := 0;

V_VLRTOTALREPASSE := 0;

V_VLRDEVIDO := 0;

-- Os valores informados pelo formulário de parâmetros, podem ser obtidos com as funções:
--     ACT_INT_PARAM
--     ACT_DEC_PARAM
--     ACT_TXT_PARAM
--     ACT_DTA_PARAM
-- Estas funções recebem 2 argumentos:
--     ID DA SESSÃO - Identificador da execução (Obtido através de P_IDSESSAO))
--     NOME DO PARAMETRO - Determina qual parametro deve se deseja obter.
FOR I IN 1..P_QTDLINHAS -- Este loop permite obter o valor de campos dos registros envolvidos na execução.
LOOP -- A variável "I" representa o registro corrente.
-- Para obter o valor dos campos utilize uma das seguintes funções:
--     ACT_INT_FIELD (Retorna o valor de um campo tipo NUMÉRICO INTEIRO))
--     ACT_DEC_FIELD (Retorna o valor de um campo tipo NUMÉRICO FLOAT))
--     ACT_TXT_FIELD (Retorna o valor de um campo tipo TEXTO),
--     ACT_DTA_FIELD (Retorna o valor de um campo tipo DATA)
-- Estas funções recebem 3 argumentos:
--     ID DA SESSÃO - Identificador da execução (Obtido através do parâmetro P_IDSESSAO))
--     NÚMERO DA LINHA - Relativo a qual linha selecionada.
--     NOME DO CAMPO - Determina qual campo deve ser obtido.
FIELD_NUNICO := ACT_INT_FIELD(P_IDSESSAO, I, 'NUNICO');

SELECT
    CODPARC,
    CODEMP,
    NVL(PROCESSOU, 'N') INTO V_CODPARC,
    V_CODEMP,
    V_PROCESSOU
FROM
    AD_PLANVDCON
WHERE
    NUNICO = FIELD_NUNICO;

SELECT
    MAX(DHALTER) INTO V_DHTIPOPER
FROM
    TGFTOP
WHERE
    CODTIPOPER = 1100;

SELECT
    MAX(DHALTER) INTO V_DHTIPOPERFIN
FROM
    TGFTOP
WHERE
    CODTIPOPER = 900;

IF V_PROCESSOU = 'S' THEN RAISE_APPLICATION_ERROR(-20101, '<b>Planilha já foi processada!</b>');

END IF;

/************************************* INICIO DA BUSCA DOS PRODUTOS IMPORTADOS DA PLANILHA PARA PROCESSAMENTO ***************************************/
FOR ITEM IN (
    SELECT
        CON.CODPARC,
        ITE.CODPROD,
        ITE.QTDVEND,
        ITE.VLRTOT,
        (ITE.VLRTOT / ITE.QTDVEND) AS VLRUNIT,
        ROUND((ITE.VLRTOT * 0.75), 2) AS VLRREPASSE
    FROM
        AD_PLANVDCONITE ITE
        INNER JOIN AD_PLANVDCON CON ON ITE.NUNICO = CON.NUNICO
    WHERE
        ITE.NUNICO = FIELD_NUNICO
        AND ITE.QTDVEND > 0
) LOOP
SELECT
    ROUND(ITE.VLRUNIT / VOA.QUANTIDADE, 2) * ITEM.QTDVEND INTO V_VLRARECITEM
FROM
    TGFITE ITE
    INNER JOIN TGFVOA VOA ON ITE.CODPROD = VOA.CODPROD
WHERE
    ITE.NUNOTA = (
        SELECT
            MAX(I.NUNOTA) --, VLRUNIT, ITE.QTDNEG, ITE.CODVOL
        FROM
            TGFCAB CAB
            INNER JOIN TGFITE I ON CAB.NUNOTA = I.NUNOTA
        WHERE
            CAB.CODPARC = ITEM.CODPARC
            AND I.CODPROD = ITEM.CODPROD
    )
    AND ITE.CODPROD = ITEM.CODPROD;

--RAISE_APPLICATION_ERROR(-20101,'VALOR>>>>>>>>>>>>'|| ITEM.VLRREPASSE);
/*CALCULA O VALOR DA REMUNERAÇÃO QUE É O TOTAL DO REPASSE - O VALOR DEVIDO */
V_REMUNERACAO := V_REMUNERACAO + ITEM.VLRREPASSE - V_VLRARECITEM;

V_VLRTOTALREPASSE := V_VLRTOTALREPASSE + ITEM.VLRREPASSE;

V_VLRDEVIDO := V_VLRDEVIDO + V_VLRARECITEM;

END LOOP;

--RAISE_APPLICATION_ERROR(-20101,'VALOR>>>>>>>>>>>>'|| V_VLRTOTALREPASSE ||'>>>>>'||V_VLRDEVIDO||'>>>>>>>'||V_REMUNERACAO||'>>>>>>>>>>'||V_VLRARECITEM);
IF V_VLRTOTALREPASSE >= V_VLRDEVIDO THEN V_VLRTOTABAIXA := V_VLRDEVIDO;

V_REMUNERACAO := V_VLRTOTALREPASSE - V_VLRDEVIDO;

END IF;

--RAISE_APPLICATION_ERROR(-20101,'VALOR>>>>>>>>>>>>'|| V_VLRTOTALREPASSE ||'>>>>>'||V_VLRDEVIDO||'>>>>>>>'||V_REMUNERACAO||'>>>>>>>>>>'||V_VLRARECITEM);
IF V_VLRTOTALREPASSE < V_VLRDEVIDO THEN V_VLRTOTABAIXA := V_VLRTOTALREPASSE;

--V_REMUNERACAO := 0;
END IF;

--RAISE_APPLICATION_ERROR(-20101,'VALOR>>>>>>>>>>>>'|| V_VLRTOTALREPASSE ||'>>>>>'||V_VLRDEVIDO||'>>>>>>>'||V_REMUNERACAO||'>>>>'||V_VLRTOTABAIXA);
/*************************************************FIM DA BUSCA DOS PRODUTOS IMPORTADOS DA PLANILHA PARA PROCESSAMENTO*******************************************************************/
/**************************************************************************  INICIO DO PROCESSAMENTO DA PLANILHA ****************************************************************************/
FOR F IN (
    SELECT
        AD_NUANTECIP,
        NUFIN,
        CODEMP,
        NUMNOTA,
        DTNEG,
        DHMOV,
        FIN.CODPARC,
        CODTIPOPER,
        DHTIPOPER,
        CODBCO,
        CODCTABCOINT,
        CODNAT,
        CODCENCUS,
        CODVEND,
        CODMOEDA,
        CODTIPTIT,
        VLRDESDOB,
        VLRCHEQUE,
        CODEMPBAIXA,
        VLRVENDOR,
        VLRIRF,
        VLRISS,
        DESPCART,
        ISSRETIDO,
        VLRDESC,
        VLRMULTA,
        VLRINSS,
        VLRJURO,
        BASEICMS,
        ALIQICMS,
        DTVENC,
        CODTIPOPERBAIXA,
        DHTIPOPERBAIXA,
        VLRBAIXA,
        AUTORIZADO,
        RECDESP,
        PROVISAO,
        ORIGEM,
        TIPMARCCHEQ,
        RATEADO,
        VLRPROV,
        INSSRETIDO,
        DTALTER,
        NUMCONTRATO,
        ORDEMCARGA,
        CODVEICULO,
        CODUSU,
        HISTORICO,
        DESDOBRAMENTO,
        CODREGUA,
        NOSSONUM,
        (
            NVL(FIN.VLRDESDOB, 0) + (
                CASE
                    WHEN FIN.TIPMULTA = '1' THEN NVL(FIN.VLRMULTA, 0)
                    ELSE 0
                END
            ) + (
                CASE
                    WHEN FIN.TIPJURO = '1' THEN NVL(FIN.VLRJURO, 0)
                    ELSE 0
                END
            ) + NVL(FIN.DESPCART, 0) + NVL(FIN.VLRVENDOR, 0) - NVL(FIN.VLRDESC, 0) - (
                CASE
                    WHEN FIN.IRFRETIDO = 'S' THEN NVL(FIN.VLRIRF, 0)
                    ELSE 0
                END
            ) - (
                CASE
                    WHEN FIN.ISSRETIDO = 'S' THEN NVL(FIN.VLRISS, 0)
                    ELSE 0
                END
            ) - (
                CASE
                    WHEN FIN.INSSRETIDO = 'S' THEN NVL(FIN.VLRINSS, 0)
                    ELSE 0
                END
            ) - NVL(FIN.CARTAODESC, 0) + NVL(
                (
                    SELECT
                        ROUND(SUM(I.VALOR * I.TIPIMP), 2)
                    FROM
                        TGFIMF I
                    WHERE
                        I.NUFIN = FIN.NUFIN
                ),
                0
            ) + NVL(FIN.VLRMULTANEGOC, 0) + NVL(FIN.VLRJURONEGOC, 0) - NVL(FIN.VLRMULTALIB, 0) - NVL(FIN.VLRJUROLIB, 0) + NVL(FIN.VLRVARCAMBIAL, 0)
        ) * NVL(FIN.RECDESP, 0) VLRLIQ
    FROM
        TGFFIN FIN
        INNER JOIN AD_GERCON GER ON FIN.CODPARC = GER.CODPARC
    WHERE
        DHBAIXA IS NULL
        AND FIN.CODPARC = V_CODPARC
    ORDER BY
        DTNEG
) LOOP
/*********INICIO DO PROCESSAMENTO QUANDO O VALOR DO TÍTULO SEJA MAIOR QUE O VALOR REPASSADO E SERÁ REALIZADA A BAIXA PARCIAL**********/
/*********************CASO O VALOR DO TÍTULO SEJA MAIOR QUE O VALOR A BAIXAR, SERÁ REALIZADA A BAIXA PARCIAL DO TÍTULO***************************/
--IF V_VLRTOTABAIXA > 0  AND (F.VLRDESDOB - F.VLRDESC) > V_VLRTOTABAIXA THEN
IF V_VLRTOTABAIXA > 0
AND F.VLRLIQ > V_VLRTOTABAIXA THEN
/* Insere na TGFMBC as informações da Baixa */
SELECT
    NVL(MAX(NUBCO) + 1, 1) INTO V_NEWNUBCO
FROM
    TGFMBC;

INSERT INTO
    TGFMBC (
        AD_NUANTECIP,
        CODCTABCOCONTRA,
        CODCTABCOINT,
        CODLANC,
        CODPDV,
        CODTIPOPER,
        CODUSU,
        CONCILIADO,
        DHCONCILIACAO,
        DHTIPOPER,
        DTALTER,
        DTCONTAB,
        DTINCLUSAO,
        DTLANC,
        HISTORICO,
        NUBCO,
        NUBCOCP,
        NUMDOC,
        NUMTRANSF,
        ORIGMOV,
        PREDATA,
        RECDESP,
        SALDO,
        TALAO,
        VLRLANC,
        VLRMOEDA
    )
VALUES
    (
        F.AD_NUANTECIP,
        NULL,
        F.CODCTABCOINT,
        1,
        null,
        1100,
        0,
        'N',
        null,
        V_DHTIPOPER,
        SYSDATE,
        NULL,
        SYSDATE,
        SYSDATE,
        '',
        V_NEWNUBCO,
        NULL,
        F.NUMNOTA,
        NULL,
        'F',
        SYSDATE,
        1,
        0,
        NULL,
        V_VLRTOTABAIXA,
        0
    );

/* INSERE NA TGFFIN O NOVO TÍTULO COM O VALOR RESTANTE*/
SELECT
    NVL(MAX(NUFIN) + 1, 1) INTO V_NEWNUFIN
FROM
    TGFFIN;

V_NEWVLRDESDOB := F.VLRDESDOB - V_VLRTOTABAIXA;

INSERT INTO
    TGFFIN (
        AD_NUANTECIP,
        NUFIN,
        CODEMP,
        NUMNOTA,
        DTNEG,
        DHMOV,
        CODPARC,
        CODTIPOPER,
        DHTIPOPER,
        CODBCO,
        CODCTABCOINT,
        CODNAT,
        CODCENCUS,
        CODVEND,
        CODMOEDA,
        CODTIPTIT,
        VLRDESDOB,
        VLRCHEQUE,
        CODEMPBAIXA,
        VLRVENDOR,
        VLRIRF,
        VLRISS,
        DESPCART,
        ISSRETIDO,
        VLRDESC,
        VLRMULTA,
        VLRINSS,
        VLRJURO,
        BASEICMS,
        ALIQICMS,
        DTVENC,
        CODTIPOPERBAIXA,
        DHTIPOPERBAIXA,
        VLRBAIXA,
        AUTORIZADO,
        RECDESP,
        PROVISAO,
        ORIGEM,
        TIPMARCCHEQ,
        RATEADO,
        VLRPROV,
        INSSRETIDO,
        DTALTER,
        NUMCONTRATO,
        ORDEMCARGA,
        CODVEICULO,
        CODUSU,
        HISTORICO,
        DESDOBRAMENTO,
        CODREGUA,
        NUBCO
    )
VALUES
    (
        F.AD_NUANTECIP,
        V_NEWNUFIN,
        F.CODEMP,
        F.NUMNOTA,
        F.DTNEG,
        F.DHMOV,
        F.CODPARC,
        F.CODTIPOPER,
        F.DHTIPOPER,
        F.CODBCO,
        F.CODCTABCOINT,
        F.CODNAT,
        F.CODCENCUS,
        0,
        F.CODMOEDA,
        F.CODTIPTIT,
        V_NEWVLRDESDOB,
        F.VLRCHEQUE,
        F.CODEMPBAIXA,
        F.VLRVENDOR,
        F.VLRIRF,
        F.VLRISS,
        F.DESPCART,
        F.ISSRETIDO,
        0,
        F.VLRMULTA,
        F.VLRINSS,
        F.VLRJURO,
        F.BASEICMS,
        F.ALIQICMS,
        F.DTVENC,
        F.CODTIPOPERBAIXA,
        F.DHTIPOPERBAIXA,
        F.VLRBAIXA,
        F.AUTORIZADO,
        F.RECDESP,
        F.PROVISAO,
        F.ORIGEM,
        F.TIPMARCCHEQ,
        F.RATEADO,
        F.VLRPROV,
        F.INSSRETIDO,
        F.DTALTER,
        F.NUMCONTRATO,
        F.ORDEMCARGA,
        F.CODVEICULO,
        F.CODUSU,
        F.HISTORICO,
        F.DESDOBRAMENTO,
        F.CODREGUA,
        V_NEWNUBCO
    );

/* INSERE NA TGFFRE INFORMAÇÕES DO NOVO TÍTULO PASSADO COMO NUFIN*/
SELECT
    NVL(MAX(NUACERTO) + 1, 1) INTO V_NEWNUACERTO
FROM
    TGFFRE;

INSERT INTO
    TGFFRE (
        CODUSU,
        DHALTER,
        NUACERTO,
        NUFIN,
        NUFINORIG,
        NUNOTA,
        SEQUENCIA,
        TIPACERTO
    )
VALUES
    (
        0,
        SYSDATE,
        V_NEWNUACERTO,
        V_NEWNUFIN,
        NULL,
        NULL,
        1,
        'P'
    );

/*INSERE DA TGFFRE INFORMAÇÕES DO TÍTULO BAIXADO PARCIALMENTE(ORIGINAL)*/
/*
 SELECT NVL(MAX(NUACERTO)+1,1) INTO V_NEWNUACERTO
 FROM TGFFRE;*/
INSERT INTO
    TGFFRE (
        CODUSU,
        DHALTER,
        NUACERTO,
        NUFIN,
        NUFINORIG,
        NUNOTA,
        SEQUENCIA,
        TIPACERTO
    )
VALUES
    (
        0,
        SYSDATE,
        V_NEWNUACERTO,
        F.NUFIN,
        NULL,
        NULL,
        2,
        'P'
    );

/*Atualiza a TGFFIN as informações da baixa no título original*/
UPDATE
    TGFFIN
SET
    CODEMPBAIXA = F.CODEMP,
    CODTIPOPERBAIXA = 1100,
    CODUSUBAIXA = 0,
    DHBAIXA = SYSDATE,
    DHTIPOPERBAIXA = V_DHTIPOPER,
    DTALTER = SYSDATE,
    NOSSONUM = F.NOSSONUM,
    NUBCO = V_NEWNUBCO,
    VLRBAIXA = V_VLRTOTABAIXA,
    VLRCHEQUE = V_VLRTOTABAIXA,
    VLRDESDOB = V_VLRTOTABAIXA + F.VLRDESC,
    VLRVARCAMBIAL = 0,
    VLRDESC = F.VLRDESC
WHERE
    TGFFIN.NUFIN = F.NUFIN;

V_VLRTOTABAIXA := 0;

INSERT INTO
    AD_ADPLANVDCONTIT(NUNICO, NUFIN)
VALUES
    (FIELD_NUNICO, F.NUFIN);

END IF;

/*********FIM DO PROCESSAMENTO QUANDO O VALOR DO TÍTULO SEJA MAIOR QUE O VALOR REPASSADO E SERÁ REALIZADA A BAIXA PARCIAL**********/
/*********INICIO DO PROCESSAMENTO QUANDO O VALOR DO TÍTULO SEJA MENOR QUE O VALOR REPASSADO E SERÁ REALIZADA A BAIXA TOTAL**********/
/*CASO O VALOR DO TÍTULO SEJA MENOR QUE O VALOR A BAIXAR, DEVEREMOS EFETUAR A BAIXA TOTAL DO TÍTULO*/
--IF (F.VLRDESDOB - F.VLRDESC) <= V_VLRTOTABAIXA AND  V_VLRTOTABAIXA > 0 THEN
IF F.VLRLIQ <= V_VLRTOTABAIXA
AND V_VLRTOTABAIXA > 0 THEN
/* Insere na TGFMBC as informações da Baixa */
SELECT
    NVL(MAX(NUBCO) + 1, 1) INTO V_NEWNUBCO
FROM
    TGFMBC;

INSERT INTO
    TGFMBC (
        AD_NUANTECIP,
        CODCTABCOCONTRA,
        CODCTABCOINT,
        CODLANC,
        CODPDV,
        CODTIPOPER,
        CODUSU,
        CONCILIADO,
        DHCONCILIACAO,
        DHTIPOPER,
        DTALTER,
        DTCONTAB,
        DTINCLUSAO,
        DTLANC,
        HISTORICO,
        NUBCO,
        NUBCOCP,
        NUMDOC,
        NUMTRANSF,
        ORIGMOV,
        PREDATA,
        RECDESP,
        SALDO,
        TALAO,
        VLRLANC,
        VLRMOEDA
    )
VALUES
    (
        F.AD_NUANTECIP,
        NULL,
        F.CODCTABCOINT,
        1,
        null,
        1100,
        0,
        'N',
        null,
        V_DHTIPOPER,
        SYSDATE,
        NULL,
        SYSDATE,
        SYSDATE,
        '',
        V_NEWNUBCO,
        NULL,
        F.NUMNOTA,
        NULL,
        'F',
        SYSDATE,
        1,
        0,
        NULL,
        (F.VLRDESDOB - F.VLRDESC),
        0
    );

/*EFETUAR UPDATE COM DADOS DA BAIXA NA TGFFIN */
UPDATE
    TGFFIN
SET
    CODEMPBAIXA = F.CODEMP,
    CODTIPOPERBAIXA = 1100,
    CODUSUBAIXA = 0,
    DHBAIXA = SYSDATE,
    DHTIPOPERBAIXA = V_DHTIPOPER,
    DTALTER = SYSDATE,
    NOSSONUM = F.NOSSONUM,
    NUBCO = V_NEWNUBCO,
    VLRBAIXA = (F.VLRDESDOB - F.VLRDESC),
    VLRCHEQUE = (F.VLRDESDOB - F.VLRDESC),
    VLRDESDOB = (F.VLRDESDOB - F.VLRDESC),
    VLRVARCAMBIAL = 0
WHERE
    TGFFIN.NUFIN = F.NUFIN;

V_VLRTOTABAIXA := V_VLRTOTABAIXA - (F.VLRDESDOB - F.VLRDESC);

/* RECALCULAR  V_VLRTOTABAIXA COM O SALDO APÓS A BAIXA DO TITULO*/
INSERT INTO
    AD_ADPLANVDCONTIT(NUNICO, NUFIN)
VALUES
    (FIELD_NUNICO, F.NUFIN);

END IF;

END LOOP;

/*LANCAR NOVO TÍTULO REFERENTE A REMUNERAÇÃO*/
/************************* INÍCIO INSERE NA TGFFIN O NOVO TÍTULO REFERENTE A REMUNERAÇÃO */
IF (
    V_REMUNERACAO IS NOT NULL
    AND V_REMUNERACAO >= 0
) THEN
SELECT
    NVL(MAX(NUFIN) + 1, 1) INTO V_NEWNUFIN
FROM
    TGFFIN;

IF(V_REMUNERACAO > 0) THEN
INSERT INTO
    TGFFIN (
        AD_NUANTECIP,
        NUFIN,
        CODEMP,
        NUMNOTA,
        DTNEG,
        DHMOV,
        CODPARC,
        CODTIPOPER,
        DHTIPOPER,
        CODBCO,
        CODCTABCOINT,
        CODNAT,
        CODCENCUS,
        CODVEND,
        CODMOEDA,
        CODTIPTIT,
        VLRDESDOB,
        VLRCHEQUE,
        CODEMPBAIXA,
        VLRVENDOR,
        VLRIRF,
        VLRISS,
        DESPCART,
        ISSRETIDO,
        VLRDESC,
        VLRMULTA,
        VLRINSS,
        VLRJURO,
        BASEICMS,
        ALIQICMS,
        DTVENC,
        AUTORIZADO,
        RECDESP,
        PROVISAO,
        ORIGEM,
        TIPMARCCHEQ,
        RATEADO,
        VLRPROV,
        INSSRETIDO,
        DTALTER,
        NUMCONTRATO,
        ORDEMCARGA,
        CODVEICULO,
        CODUSU,
        HISTORICO,
        DESDOBRAMENTO,
        CODREGUA,
        NUBCO
    )
VALUES
    (
        null,
        V_NEWNUFIN,
        V_CODEMP,
        0,
        TO_DATE(SYSDATE, 'DD/MM/RRRR'),
        sysdate,
        V_CODPARC,
        '900',
        V_DHTIPOPERFIN,
        '341',
        '3',
        '1010110',
        '10700',
        0,
        '0',
        '4',
        ROUND(V_REMUNERACAO, 2),
        ROUND(V_REMUNERACAO, 2),
        null,
        '0',
        '0',
        '0',
        '0',
        'N',
        '0',
        '0',
        '0',
        '0',
        '0',
        '0',
        ADD_MONTHS(SYSDATE, 2),
        'N',
        '1',
        'N',
        'F',
        'I',
        'N',
        '0',
        'N',
        SYSDATE,
        '0',
        0,
        '0',
        0,
        'REMUNERAÇÃO DE CONSIGNAÇÃO COMPETÊNCIA ' || TO_CHAR(SYSDATE, 'MM/YYYY'),
        '1',
        null,
        null
    );

END IF;

--RAISE_APPLICATION_ERROR(-20101,'VALOR>>>>>>>>>>>>'|| V_VLRTOTABAIXA ||'>>>>>'||'>>>>>>>'||V_NEWVLRDESDOB);                 
/* Insere na TGFMBC as informações da Baixa */
SELECT
    NVL(MAX(NUBCO) + 1, 1) INTO V_NEWNUBCO
FROM
    TGFMBC;

INSERT INTO
    TGFMBC (
        AD_NUANTECIP,
        CODCTABCOCONTRA,
        CODCTABCOINT,
        CODLANC,
        CODPDV,
        CODTIPOPER,
        CODUSU,
        CONCILIADO,
        DHCONCILIACAO,
        DHTIPOPER,
        DTALTER,
        DTCONTAB,
        DTINCLUSAO,
        DTLANC,
        HISTORICO,
        NUBCO,
        NUBCOCP,
        NUMDOC,
        NUMTRANSF,
        ORIGMOV,
        PREDATA,
        RECDESP,
        SALDO,
        TALAO,
        VLRLANC,
        VLRMOEDA
    )
VALUES
    (
        NULL,
        NULL,
        '3',
        1,
        null,
        1100,
        0,
        'S',
        SYSDATE,
        V_DHTIPOPER,
        SYSDATE,
        NULL,
        SYSDATE,
        SYSDATE,
        NULL,
        V_NEWNUBCO,
        NULL,
        NULL,
        NULL,
        'F',
        SYSDATE,
        1,
        0,
        NULL,
        ROUND(V_REMUNERACAO, 2),
        0
    );

/*EFETUAR UPDATE COM DADOS DA BAIXA NA TGFFIN */
UPDATE
    TGFFIN
SET
    CODEMPBAIXA = V_CODEMP,
    CODTIPOPERBAIXA = 1100,
    CODUSUBAIXA = 0,
    DHBAIXA = SYSDATE,
    DHTIPOPERBAIXA = V_DHTIPOPER,
    DTALTER = SYSDATE,
    NUBCO = V_NEWNUBCO,
    VLRBAIXA = ROUND(V_REMUNERACAO, 2),
    VLRCHEQUE = ROUND(V_REMUNERACAO, 2),
    VLRVARCAMBIAL = 0
WHERE
    TGFFIN.NUFIN = V_NEWNUFIN;

END IF;

/************************* INÍCIO INSERE NA TGFFIN O NOVO TÍTULO REFERENTE A REMUNERAÇÃO */
IF (
    V_REMUNERACAO IS NOT NULL
    AND V_REMUNERACAO < 0
) THEN
SELECT
    NUFIN,
    (
        NVL(FIN.VLRDESDOB, 0) + (
            CASE
                WHEN FIN.TIPMULTA = '1' THEN NVL(FIN.VLRMULTA, 0)
                ELSE 0
            END
        ) + (
            CASE
                WHEN FIN.TIPJURO = '1' THEN NVL(FIN.VLRJURO, 0)
                ELSE 0
            END
        ) + NVL(FIN.DESPCART, 0) + NVL(FIN.VLRVENDOR, 0) - NVL(FIN.VLRDESC, 0) - (
            CASE
                WHEN FIN.IRFRETIDO = 'S' THEN NVL(FIN.VLRIRF, 0)
                ELSE 0
            END
        ) - (
            CASE
                WHEN FIN.ISSRETIDO = 'S' THEN NVL(FIN.VLRISS, 0)
                ELSE 0
            END
        ) - (
            CASE
                WHEN FIN.INSSRETIDO = 'S' THEN NVL(FIN.VLRINSS, 0)
                ELSE 0
            END
        ) - NVL(FIN.CARTAODESC, 0) + NVL(
            (
                SELECT
                    ROUND(SUM(I.VALOR * I.TIPIMP), 2)
                FROM
                    TGFIMF I
                WHERE
                    I.NUFIN = FIN.NUFIN
            ),
            0
        ) + NVL(FIN.VLRMULTANEGOC, 0) + NVL(FIN.VLRJURONEGOC, 0) - NVL(FIN.VLRMULTALIB, 0) - NVL(FIN.VLRJUROLIB, 0) + NVL(FIN.VLRVARCAMBIAL, 0)
    ) * NVL(FIN.RECDESP, 0) VLRLIQ,
    VLRDESC,
    AD_HISTORIDOVDACONT INTO V_NUFIN,
    V_VLRLIQ,
    V_VLRDESC,
    V_HISTORICOVNDACONTADA
FROM
    TGFFIN FIN
    INNER JOIN AD_GERCON GER ON FIN.CODPARC = GER.CODPARC
WHERE
    DHBAIXA IS NULL
    AND (
        (
            NVL(FIN.VLRDESDOB, 0) + (
                CASE
                    WHEN FIN.TIPMULTA = '1' THEN NVL(FIN.VLRMULTA, 0)
                    ELSE 0
                END
            ) + (
                CASE
                    WHEN FIN.TIPJURO = '1' THEN NVL(FIN.VLRJURO, 0)
                    ELSE 0
                END
            ) + NVL(FIN.DESPCART, 0) + NVL(FIN.VLRVENDOR, 0) - NVL(FIN.VLRDESC, 0) - (
                CASE
                    WHEN FIN.IRFRETIDO = 'S' THEN NVL(FIN.VLRIRF, 0)
                    ELSE 0
                END
            ) - (
                CASE
                    WHEN FIN.ISSRETIDO = 'S' THEN NVL(FIN.VLRISS, 0)
                    ELSE 0
                END
            ) - (
                CASE
                    WHEN FIN.INSSRETIDO = 'S' THEN NVL(FIN.VLRINSS, 0)
                    ELSE 0
                END
            ) - NVL(FIN.CARTAODESC, 0) + NVL(
                (
                    SELECT
                        ROUND(SUM(I.VALOR * I.TIPIMP), 2)
                    FROM
                        TGFIMF I
                    WHERE
                        I.NUFIN = FIN.NUFIN
                ),
                0
            ) + NVL(FIN.VLRMULTANEGOC, 0) + NVL(FIN.VLRJURONEGOC, 0) - NVL(FIN.VLRMULTALIB, 0) - NVL(FIN.VLRJUROLIB, 0) + NVL(FIN.VLRVARCAMBIAL, 0)
        ) * NVL(FIN.RECDESP, 0)
    ) > V_REMUNERACAO
    AND FIN.CODPARC = V_CODPARC
    AND DTNEG = (
        SELECT
            MIN(DTNEG)
        FROM
            TGFFIN
        WHERE
            CODPARC = V_CODPARC
            AND DHBAIXA IS NULL
    )
ORDER BY
    DTNEG;

/*EFETUAR UPDATE COM DADOS DA BAIXA NA TGFFIN */
UPDATE
    TGFFIN
SET
    VLRDESC = (V_VLRDESC + (V_REMUNERACAO * -1)),
    AD_HISTORIDOVDACONT = V_HISTORICOVNDACONTADA || SYSDATE || ' - DESCONTO NO VALOR DE ' || V_REMUNERACAO || ' APLICADO REFERENTE A REMUNERAÇÃO NEGATIVA!'
WHERE
    TGFFIN.NUFIN = V_NUFIN;

END IF;

UPDATE
    AD_PLANVDCON
SET
    PROCESSOU = 'S'
WHERE
    NUNICO = FIELD_NUNICO;

END LOOP;

-- <ESCREVA SEU CÓDIGO DE FINALIZAÇÃO AQUI> --
END;