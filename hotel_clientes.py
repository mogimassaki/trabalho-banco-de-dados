#!/usr/bin/env python3
"""
Rede de Hotéis - Cadastro de Clientes
Trabalho em Grupo - Banco de Dados I

Programa de console que insere, atualiza, exclui e consulta registros nas
tabelas CLIENTE, TELEFONE_CLIENTE e EMAIL_CLIENTE do banco "rede_hoteis",
controlando cada operação com transação (START TRANSACTION, COMMIT e ROLLBACK).

Por que essas três tabelas? Um cliente só está completo com seus telefones e
e-mails, que ficam em tabelas separadas (atributos multivalorados). Gravar o
cliente e os contatos é, portanto, UMA operação lógica que mexe em TRÊS
tabelas: ou grava tudo (COMMIT), ou não grava nada (ROLLBACK).

Requisitos:
    pip install mysql-connector-python
    banco criado com o script rede_hoteis.sql

Conexão: altere o dicionário CONFIG abaixo ou defina as variáveis de ambiente
DB_HOST, DB_PORT, DB_USER, DB_PASSWORD e DB_NAME.
"""

import os
import re
import sys
from datetime import datetime

import mysql.connector

CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", "3306")),
    "user": os.getenv("DB_USER", "root"),
    "password": os.getenv("DB_PASSWORD", ""),
    "database": os.getenv("DB_NAME", "rede_hoteis"),
    "charset": "utf8mb4",
}

EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


# =============================================================================
# Validações
# =============================================================================

def so_digitos(texto):
    return re.sub(r"\D", "", texto)


def cpf_valido(cpf):
    """Confere os dois dígitos verificadores do CPF (só dígitos, 11 posições)."""
    if len(cpf) != 11 or cpf == cpf[0] * 11:
        return False
    for posicao in (9, 10):
        soma = sum(int(cpf[i]) * (posicao + 1 - i) for i in range(posicao))
        digito = (soma * 10) % 11 % 10
        if digito != int(cpf[posicao]):
            return False
    return True


def formatar_cpf(cpf):
    return f"{cpf[:3]}.{cpf[3:6]}.{cpf[6:9]}-{cpf[9:]}"


# =============================================================================
# Acesso a dados: só SQL, sem COMMIT/ROLLBACK.
# Quem decide se grava ou desfaz é executar_em_transacao().
# =============================================================================

def inserir_cliente(cur, cliente, telefones, emails):
    cur.execute(
        """INSERT INTO cliente (cpf, nome, rg, data_nascimento, logradouro,
                                numero, complemento, bairro, cidade)
            VALUES (%(cpf)s, %(nome)s, %(rg)s, %(data_nascimento)s, %(logradouro)s,
                    %(numero)s, %(complemento)s, %(bairro)s, %(cidade)s)""",
        cliente,
    )
    for telefone in telefones:
        cur.execute(
            "INSERT INTO telefone_cliente (cpf_cliente, telefone) VALUES (%s, %s)",
            (cliente["cpf"], telefone),
        )
    for email in emails:
        cur.execute(
            "INSERT INTO email_cliente (cpf_cliente, email) VALUES (%s, %s)",
            (cliente["cpf"], email),
        )
    return (f"  INSERT cliente: 1 linha | INSERT telefone_cliente: {len(telefones)} "
            f"linha(s) | INSERT email_cliente: {len(emails)} linha(s)")


def buscar_cliente(cur, cpf):
    cur.execute("SELECT * FROM vw_cliente WHERE cpf = %s", (cpf,))
    cliente = cur.fetchone()
    if cliente is None:
        return None
    cur.execute(
        "SELECT telefone FROM telefone_cliente WHERE cpf_cliente = %s ORDER BY telefone",
        (cpf,),
    )
    cliente["telefones"] = [linha["telefone"] for linha in cur.fetchall()]
    cur.execute(
        "SELECT email FROM email_cliente WHERE cpf_cliente = %s ORDER BY email",
        (cpf,),
    )
    cliente["emails"] = [linha["email"] for linha in cur.fetchall()]
    cur.execute("SELECT COUNT(*) AS total FROM reserva WHERE cpf_cliente = %s", (cpf,))
    cliente["reservas"] = cur.fetchone()["total"]
    return cliente


def listar_clientes(cur, trecho_nome=""):
    cur.execute(
        """SELECT v.cpf, v.nome, v.idade, v.cidade,
                    (SELECT GROUP_CONCAT(t.telefone ORDER BY t.telefone SEPARATOR ', ')
                        FROM telefone_cliente t WHERE t.cpf_cliente = v.cpf) AS telefones,
                    (SELECT GROUP_CONCAT(e.email ORDER BY e.email SEPARATOR ', ')
                        FROM email_cliente e WHERE e.cpf_cliente = v.cpf) AS emails
            FROM vw_cliente v
            WHERE v.nome LIKE %s
            ORDER BY v.nome""",
        (f"%{trecho_nome}%",),
    )
    return cur.fetchall()


def atualizar_cliente(cur, cpf, dados, telefones=None, emails=None):
    """Atualiza o cliente. Telefones/e-mails = None significa 'manter como está'."""
    cur.execute(
        """UPDATE cliente
                SET nome = %(nome)s, rg = %(rg)s, data_nascimento = %(data_nascimento)s,
                    logradouro = %(logradouro)s, numero = %(numero)s,
                    complemento = %(complemento)s, bairro = %(bairro)s, cidade = %(cidade)s
            WHERE cpf = %(cpf)s""",
        {**dados, "cpf": cpf},
    )
    resumo = [f"  UPDATE cliente: {cur.rowcount} linha(s) alterada(s)"]
    if telefones is not None:
        cur.execute("DELETE FROM telefone_cliente WHERE cpf_cliente = %s", (cpf,))
        resumo.append(f"DELETE telefone_cliente: {cur.rowcount}")
        for telefone in telefones:
            cur.execute(
                "INSERT INTO telefone_cliente (cpf_cliente, telefone) VALUES (%s, %s)",
                (cpf, telefone),
            )
        resumo.append(f"INSERT telefone_cliente: {len(telefones)}")
    if emails is not None:
        cur.execute("DELETE FROM email_cliente WHERE cpf_cliente = %s", (cpf,))
        resumo.append(f"DELETE email_cliente: {cur.rowcount}")
        for email in emails:
            cur.execute(
                "INSERT INTO email_cliente (cpf_cliente, email) VALUES (%s, %s)",
                (cpf, email),
            )
        resumo.append(f"INSERT email_cliente: {len(emails)}")
    return " | ".join(resumo)


def excluir_cliente(cur, cpf):
    # Telefones e e-mails saem juntos (ON DELETE CASCADE).
    # Se o cliente tiver reservas, a FK de RESERVA bloqueia (ON DELETE RESTRICT).
    cur.execute("DELETE FROM cliente WHERE cpf = %s", (cpf,))
    return f"  DELETE cliente: {cur.rowcount} linha(s) (telefones e e-mails em cascata)"


def contar_cliente(cur, cpf):
    cur.execute("SELECT COUNT(*) AS total FROM cliente WHERE cpf = %s", (cpf,))
    return cur.fetchone()["total"]


# =============================================================================
# Controle de transação
# =============================================================================

def traduzir_erro(erro):
    mensagens = {
        1062: "registro duplicado (o CPF, telefone ou e-mail já está cadastrado)",
        1451: "o registro é usado por outra tabela (ex.: o cliente possui reservas)",
        1452: "referência a um registro que não existe",
        1406: "um dos textos é maior do que o tamanho permitido na coluna",
        3819: "um valor viola uma regra CHECK da tabela",   # MySQL
        4025: "um valor viola uma regra CHECK da tabela",   # MariaDB
    }
    return f"{mensagens.get(erro.errno, 'erro inesperado')} [{erro.errno}: {erro.msg}]"


def executar_em_transacao(conn, operacao, pedir_confirmacao=True):
    """
    START TRANSACTION -> executa a operação -> COMMIT ou ROLLBACK.

      * erro em qualquer comando SQL ...... ROLLBACK automático
      * usuário responde N na confirmação . ROLLBACK
      * tudo certo e usuário confirma ..... COMMIT
    """
    cur = conn.cursor(dictionary=True)
    try:
        conn.start_transaction()
        print("  START TRANSACTION")
        resumo = operacao(cur)
        if resumo:
            print(resumo)
        if pedir_confirmacao and not perguntar_sim_nao("  Confirmar e gravar? (S/N): "):
            conn.rollback()
            print("  ROLLBACK -> operação desfeita, nada foi gravado.")
            return False
        conn.commit()
        print("  COMMIT -> alterações gravadas no banco.")
        return True
    except mysql.connector.Error as erro:
        conn.rollback()
        print(f"  ERRO: {traduzir_erro(erro)}")
        print("  ROLLBACK -> operação desfeita, nada foi gravado.")
        return False
    except BaseException:
        # Ctrl+C ou qualquer outra falha no meio da transação também desfaz tudo
        conn.rollback()
        print("\n  ROLLBACK -> operação interrompida, nada foi gravado.")
        raise
    finally:
        cur.close()


def consultar(conn, funcao, *args):
    """Consultas rodam fora de transação explícita (autocommit ligado)."""
    cur = conn.cursor(dictionary=True)
    try:
        return funcao(cur, *args)
    finally:
        cur.close()


# =============================================================================
# Entrada de dados pelo teclado
# =============================================================================

def perguntar_sim_nao(texto):
    while True:
        resposta = input(texto).strip().upper()
        if resposta in ("S", "N"):
            return resposta == "S"
        print("  Responda S ou N.")


def ler_texto(rotulo, atual=None, obrigatorio=True, editando=False):
    """Na edição, Enter mantém o valor atual e '-' apaga um campo opcional."""
    sufixo = f" [{atual if atual is not None else ''}]" if editando else ""
    while True:
        valor = input(f"  {rotulo}{sufixo}: ").strip()
        if editando and valor == "":
            return atual
        if editando and valor == "-" and not obrigatorio:
            return None
        if valor:
            return valor
        if not obrigatorio:
            return None
        print("  Campo obrigatório.")


def ler_cpf(rotulo="CPF"):
    while True:
        cpf = so_digitos(input(f"  {rotulo}: "))
        if cpf_valido(cpf):
            return cpf
        print("  CPF inválido (confira os 11 dígitos).")


def ler_data(rotulo, atual=None, editando=False):
    while True:
        padrao = atual.strftime("%d/%m/%Y") if atual else ""
        valor = ler_texto(rotulo + " (dd/mm/aaaa)", padrao, editando=editando)
        try:
            data = datetime.strptime(valor, "%d/%m/%Y").date()
        except ValueError:
            print("  Data inválida.")
            continue
        if data > datetime.now().date():
            print("  A data de nascimento não pode estar no futuro.")
            continue
        return data


def ler_lista(rotulo, validar=None, atual=None, editando=False):
    """Lê itens separados por vírgula. Na edição, Enter mantém a lista atual."""
    if editando:
        print(f"  {rotulo} atuais: {', '.join(atual) if atual else '(nenhum)'}")
        rotulo += " (separados por vírgula; Enter mantém)"
    else:
        rotulo += " (separados por vírgula)"
    while True:
        valor = input(f"  {rotulo}: ").strip()
        if editando and valor == "":
            return None
        itens = list(dict.fromkeys(i.strip() for i in valor.split(",") if i.strip()))
        invalidos = [i for i in itens if validar and not validar(i)]
        if invalidos:
            print(f"  Valor(es) inválido(s): {', '.join(invalidos)}")
            continue
        return itens


def ler_dados_cliente(atual=None):
    editando = atual is not None
    atual = atual or {}
    return {
        "nome": ler_texto("Nome", atual.get("nome"), editando=editando),
        "rg": ler_texto("RG", atual.get("rg"), editando=editando),
        "data_nascimento": ler_data("Data de nascimento",
                                    atual.get("data_nascimento"), editando),
        "logradouro": ler_texto("Logradouro", atual.get("logradouro"), editando=editando),
        "numero": ler_texto("Número", atual.get("numero"), editando=editando),
        "complemento": ler_texto("Complemento (opcional)", atual.get("complemento"),
                                 obrigatorio=False, editando=editando),
        "bairro": ler_texto("Bairro", atual.get("bairro"), editando=editando),
        "cidade": ler_texto("Cidade", atual.get("cidade"), editando=editando),
    }


def validar_telefone(telefone):
    return 10 <= len(so_digitos(telefone)) <= 13 and len(telefone) <= 20


def validar_email(email):
    return bool(EMAIL_RE.match(email)) and len(email) <= 120


# =============================================================================
# Telas
# =============================================================================

def mostrar_cliente(c):
    endereco = f"{c['logradouro']}, {c['numero']}"
    if c["complemento"]:
        endereco += f" - {c['complemento']}"
    endereco += f" - {c['bairro']} - {c['cidade']}"
    print(f"""
  CPF ........... {formatar_cpf(c['cpf'])}
  Nome .......... {c['nome']}
  RG ............ {c['rg']}
  Nascimento .... {c['data_nascimento'].strftime('%d/%m/%Y')} ({c['idade']} anos)
  Endereço ...... {endereco}
  Telefones ..... {', '.join(c['telefones']) or '-'}
  E-mails ....... {', '.join(c['emails']) or '-'}
  Reservas ...... {c['reservas']}""")


def tela_cadastrar(conn):
    print("\n--- CADASTRAR CLIENTE ---")
    cpf = ler_cpf()
    if consultar(conn, contar_cliente, cpf):
        print("  Já existe cliente com esse CPF.")
        return
    cliente = {"cpf": cpf, **ler_dados_cliente()}
    telefones = ler_lista("Telefones", validar_telefone)
    emails = ler_lista("E-mails", validar_email)
    executar_em_transacao(
        conn, lambda cur: inserir_cliente(cur, cliente, telefones, emails))


def tela_listar(conn):
    print("\n--- LISTAR CLIENTES ---")
    trecho = input("  Filtrar por nome (Enter = todos): ").strip()
    clientes = consultar(conn, listar_clientes, trecho)
    if not clientes:
        print("  Nenhum cliente encontrado.")
        return
    print(f"\n  {'CPF':<15}{'Nome':<26}{'Idade':>5}  {'Cidade':<16}Telefones")
    print("  " + "-" * 92)
    for c in clientes:
        print(f"  {formatar_cpf(c['cpf']):<15}{c['nome'][:25]:<26}{c['idade']:>5}  "
              f"{c['cidade'][:15]:<16}{c['telefones'] or '-'}")
    print(f"\n  {len(clientes)} cliente(s).")


def tela_consultar(conn):
    print("\n--- CONSULTAR CLIENTE ---")
    cliente = consultar(conn, buscar_cliente, ler_cpf())
    if cliente is None:
        print("  Cliente não encontrado.")
    else:
        mostrar_cliente(cliente)


def tela_atualizar(conn):
    print("\n--- ATUALIZAR CLIENTE ---")
    cpf = ler_cpf()
    atual = consultar(conn, buscar_cliente, cpf)
    if atual is None:
        print("  Cliente não encontrado.")
        return
    print("  Enter mantém o valor entre colchetes; '-' apaga o complemento.")
    dados = ler_dados_cliente(atual)
    telefones = ler_lista("Telefones", validar_telefone, atual["telefones"], editando=True)
    emails = ler_lista("E-mails", validar_email, atual["emails"], editando=True)
    executar_em_transacao(
        conn, lambda cur: atualizar_cliente(cur, cpf, dados, telefones, emails))


def tela_excluir(conn):
    print("\n--- EXCLUIR CLIENTE ---")
    cpf = ler_cpf()
    cliente = consultar(conn, buscar_cliente, cpf)
    if cliente is None:
        print("  Cliente não encontrado.")
        return
    mostrar_cliente(cliente)
    executar_em_transacao(conn, lambda cur: excluir_cliente(cur, cpf))


def tela_demonstrar_rollback(conn):
    """Mostra, passo a passo, o efeito do ROLLBACK e da atomicidade."""
    print("\n--- DEMONSTRAÇÃO DE ROLLBACK ---")
    cpf = "47104974601"
    teste = {"cpf": cpf, "nome": "Cliente Teste Rollback", "rg": "0000000000",
             "data_nascimento": "1990-01-01", "logradouro": "Rua Teste",
             "numero": "1", "complemento": None, "bairro": "Centro", "cidade": "Teste"}
    if consultar(conn, contar_cliente, cpf):
        print("  O CPF de teste já existe no banco; exclua-o para rodar a demonstração.")
        return
    cur = conn.cursor(dictionary=True)
    try:
        print("\n  Parte 1 - desfazer de propósito")
        conn.start_transaction()
        print("  START TRANSACTION")
        inserir_cliente(cur, teste, ["(51) 90000-0001"], [])
        print(f"  INSERT feito. Dentro da transação, clientes com esse CPF: "
              f"{contar_cliente(cur, cpf)}")
        conn.rollback()
        print(f"  ROLLBACK. Depois do ROLLBACK, clientes com esse CPF: "
              f"{contar_cliente(cur, cpf)}")

        print("\n  Parte 2 - erro no meio da transação (atomicidade)")
        conn.start_transaction()
        print("  START TRANSACTION")
        try:
            # o segundo telefone repete o primeiro -> viola a chave primária
            inserir_cliente(cur, teste, ["(51) 90000-0001", "(51) 90000-0001"], [])
            conn.commit()
        except mysql.connector.Error as erro:
            print("  INSERT cliente OK, INSERT telefone 1 OK, INSERT telefone 2 FALHOU:")
            print(f"    {traduzir_erro(erro)}")
            conn.rollback()
            print("  ROLLBACK. O cliente inserido antes do erro também foi desfeito: "
                  f"{contar_cliente(cur, cpf)} registro(s).")
    finally:
        cur.close()


# =============================================================================
# Programa principal
# =============================================================================

MENU = """
==============================================
   REDE DE HOTÉIS - CADASTRO DE CLIENTES
==============================================
  1 - Cadastrar cliente           (INSERT)
  2 - Listar clientes             (SELECT)
  3 - Consultar cliente por CPF   (SELECT)
  4 - Atualizar cliente           (UPDATE)
  5 - Excluir cliente             (DELETE)
  6 - Demonstração de ROLLBACK
  0 - Sair"""

OPCOES = {
    "1": tela_cadastrar,
    "2": tela_listar,
    "3": tela_consultar,
    "4": tela_atualizar,
    "5": tela_excluir,
    "6": tela_demonstrar_rollback,
}


def conectar():
    try:
        conn = mysql.connector.connect(**CONFIG)
    except mysql.connector.Error as erro:
        print(f"Não foi possível conectar ao banco: {erro}")
        print("Confira usuário/senha em CONFIG e se o script rede_hoteis.sql foi executado.")
        sys.exit(1)
    # Autocommit ligado para as consultas; toda escrita abre START TRANSACTION
    # explicitamente, e nada é gravado até o COMMIT.
    conn.autocommit = True
    return conn


def main():
    conn = conectar()
    try:
        while True:
            print(MENU)
            opcao = input("Opção: ").strip()
            if opcao == "0":
                break
            tela = OPCOES.get(opcao)
            if tela is None:
                print("  Opção inválida.")
                continue
            tela(conn)
    except (KeyboardInterrupt, EOFError):
        print()
    finally:
        conn.close()
        print("Conexão encerrada.")


if __name__ == "__main__":
    main()
