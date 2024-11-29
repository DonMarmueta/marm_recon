# Marmota Recon - Domains and SubDomains
#!/bin/bash
# Define que o script será interpretado pelo shell Bash

# Script de Reconhecimento de Domínios e Subdomínios
# Code by Rafael Marmota - marmouts@proton.me

# Função para exibir um banner com cores
function show_banner() {
    RED="\033[1;31m"   # Define a cor vermelha
    GREEN="\033[1;32m" # Define a cor verde
    BLUE="\033[1;34m"  # Define a cor azul
    CYAN="\033[1;36m"  # Define a cor ciano
    RESET="\033[0m"    # Reseta a cor para o padrão do terminal

    # Exibe o banner com as cores definidas
    echo -e "${GREEN}#############################################################${RESET}"
    echo -e "${BLUE}#       ${CYAN}Reconhecimento de Domínios e Subdomínios          ${BLUE}#${RESET}"
    echo -e "${BLUE}#    🦫${CYAN}Code by Rafael Marmota - marmouts@proton.me🦫     ${BLUE}#${RESET}"
    echo -e "${GREEN}#############################################################${RESET}"
}

# Função para verificar dependências
function check_dependencies() {
    DEPENDENCIES=("assetfinder" "amass" "dnsrecon" "gobuster" "nmap") # Lista de dependências necessárias
    for dep in "${DEPENDENCIES[@]}"; do # Itera sobre cada dependência
        if ! command -v "$dep" &> /dev/null; then # Verifica se o comando existe no sistema
            echo "Erro: $dep não está instalado. Instale antes de continuar." # Mensagem de erro se a dependência estiver ausente
            exit 1 # Encerra o script com código de erro
        fi
    done
}

# Função para exibir como usar o script
function show_usage() {
    echo "Uso: $0 -d dominio [-l lista_de_dominios] [-w wordlist] [-h]" # Explica os argumentos do script
    echo "Opções:"
    echo "  -d domínio único para reconhecimento"
    echo "  -l arquivo contendo uma lista de domínios"
    echo "  -w wordlist para uso com Gobuster"
    echo "  -h mostra esta ajuda"
    exit 0 # Encerra após exibir a ajuda
}

# Inicialização de variáveis
LOG_FILE=""             # Caminho para o arquivo de log (inicialmente vazio)
DOMAIN=""               # Variável para o domínio único
DOMAIN_LIST=""          # Variável para a lista de domínios
WORDLIST="/wordlist_compact.txt" # Caminho padrão para a wordlist do Gobuster

# Processar argumentos do script
while getopts "d:l:w:h" opt; do # Lê as opções passadas na linha de comando
    case $opt in
        d) DOMAIN=$OPTARG ;;   # Se "-d" for usado, armazena o domínio na variável DOMAIN
        l) DOMAIN_LIST=$OPTARG ;; # Se "-l" for usado, armazena o caminho do arquivo de lista
        w) WORDLIST=$OPTARG ;; # Se "-w" for usado, armazena o caminho da wordlist
        h) show_usage ;;       # Se "-h" for usado, exibe a ajuda
        *) echo "Opção inválida"; show_usage ;; # Para opções inválidas, exibe a ajuda
    esac
done

# Verifica se pelo menos um domínio ou uma lista de domínios foi fornecida
if [[ -z "$DOMAIN" && -z "$DOMAIN_LIST" ]]; then
    echo "Erro: Forneça um domínio (-d) ou uma lista de domínios (-l)."
    show_usage
fi

# Verificar dependências
check_dependencies # Chama a função para verificar dependências

# Mostrar o banner
show_banner # Exibe o banner no terminal

# Criar diretório principal de saída
RESULTS_DIR="./resultados_recon" # Define o diretório principal para salvar os resultados
mkdir -p "$RESULTS_DIR" # Cria o diretório, se ele ainda não existir

# Ativar logging
LOG_FILE="$RESULTS_DIR/execution_log.txt" # Define o caminho do arquivo de log
exec > >(tee -a "$LOG_FILE") 2>&1 # Redireciona a saída do terminal para o arquivo de log

# Função para processar um único domínio
function process_domain() {
    local DOMAIN=$1 # Recebe o domínio como argumento

    echo "## Processando domínio: $DOMAIN"

    # Criar pasta para o domínio
    DOMAIN_DIR="$RESULTS_DIR/$DOMAIN" # Define uma subpasta específica para o domínio
    mkdir -p "$DOMAIN_DIR" # Cria a subpasta

    # Enumerando subdomínios com Assetfinder
    echo "## Enumerando subdomínios com Assetfinder..."
    assetfinder --subs-only "$DOMAIN" > "$DOMAIN_DIR/subdomains_assetfinder.txt" # Salva os resultados no arquivo correspondente

    # Enumerando subdomínios com Amass
    echo "## Enumerando subdomínios com Amass..."
    amass enum -d "$DOMAIN" -o "$DOMAIN_DIR/subdomains_amass.txt" # Salva os resultados no arquivo correspondente

    # Combinando resultados e removendo duplicados
    echo "## Combinando resultados e removendo duplicados..."
    cat "$DOMAIN_DIR/subdomains_assetfinder.txt" \
        "$DOMAIN_DIR/subdomains_amass.txt" | sort -u > "$DOMAIN_DIR/subdomains_final.txt" # Combina os arquivos e remove duplicados
    echo " - Subdomínios encontrados: $DOMAIN_DIR/subdomains_final.txt"

    # Verificando resolução de DNS com Dnsrecon
    echo "## Verificando resolução de DNS com Dnsrecon..."
    while read -r subdomain; do
        dnsrecon -d "$subdomain" -t std >> "$DOMAIN_DIR/dnsrecon_results.txt" # Adiciona os resultados de DNS no arquivo
    done < "$DOMAIN_DIR/subdomains_final.txt"
    echo "## Dnsrecon finalizado. Resultados salvos em: $DOMAIN_DIR/dnsrecon_results.txt"

    # Enumerando diretórios com Gobuster
    echo "## Enumerando diretórios com Gobuster..."
    if [[ ! -f "$WORDLIST" ]]; then # Verifica se a wordlist existe
        echo "Erro: Wordlist não encontrada em $WORDLIST."
        return
    fi
    gobuster dir -u "http://$DOMAIN" -w "$WORDLIST" -t 2 --status-codes-blacklist "301" -o "$DOMAIN_DIR/gobuster_results.txt"
    echo "## Gobuster finalizado. Resultados salvos em: $DOMAIN_DIR/gobuster_results.txt"

    # Varredura de portas com Nmap
    echo "## Realizando varredura de portas com Nmap..."
    nmap -T4 -sV -p- "$DOMAIN" -oN "$DOMAIN_DIR/nmap_results.txt"
    echo "## Nmap finalizado. Resultados salvos em: $DOMAIN_DIR/nmap_results.txt"

    # Compilando resultados finais
    echo "## Compilando resultados finais..."
    {
        echo "Resultados de Subdomínios:"
        cat "$DOMAIN_DIR/subdomains_final.txt"
        echo ""
        echo "Resultados de DNS:"
        cat "$DOMAIN_DIR/dnsrecon_results.txt"
        echo ""
        echo "Resultados de Gobuster:"
        cat "$DOMAIN_DIR/gobuster_results.txt"
        echo ""
        echo "Resultados de Nmap:"
        cat "$DOMAIN_DIR/nmap_results.txt"
    } > "$DOMAIN_DIR/compiled_results.txt" # Cria um arquivo compilado com todos os resultados
    echo "## Resultados compilados salvos em: $DOMAIN_DIR/compiled_results.txt"
}

# Processar domínio único ou lista de domínios
if [[ -n "$DOMAIN" ]]; then
    process_domain "$DOMAIN" # Processa um único domínio
elif [[ -f "$DOMAIN_LIST" ]]; then
    while read -r domain; do
        process_domain "$domain" # Processa cada domínio na lista
    done < "$DOMAIN_LIST"
else
    echo "Erro: Arquivo de lista de domínios não encontrado."
    exit 1 # Encerra com erro se a lista não existir
fi

echo "## Reconhecimento finalizado. Resultados disponíveis em: $RESULTS_DIR"
