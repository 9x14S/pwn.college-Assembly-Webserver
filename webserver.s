BITS 64

; PARAMETERS
%define AF_INET 2
%define SOCK_STREAM 1
%define SOCK_DGRAM 2

; SYSCALLS
%define READ 0
%define WRITE 1
%define OPEN 2
%define CLOSE 3

%define SOCKET 41
%define CONNECT 42
%define ACCEPT 43
%define BIND 49
%define LISTEN 50
%define FORK 57
%define EXIT 60

; FLAGS
%define O_RDONLY 0
%define O_WRONLY 1
%define O_CREAT 64
%define O_TRUNCAT 512

; Vars
%define BUFSIZE 0x1000
%define RESPSIZE 19

SECTION .data
        struc sockaddr_in
                .sin_family  resw 1
                .sin_port    resw 1
                .sin_addr    resd 1
                .__pad       resb 8
        endstruc
        sock_fd: dd 0
        conn_fd: dd 0
        filename: dq 0
        file_fd: dd 0
        other_data: dq 0
        req_size: dq 0


SECTION .rodata
        response db "HTTP/1.0 200 OK", 13, 10, 13, 10, 0
        post_str db "POST", 0
        get_str db "GET", 0
        data_str db 13, 10, 13, 10

SECTION .bss
        a resb sockaddr_in_size

        buffer resb BUFSIZE

SECTION .text
global _start
_start:
        ; sock_fd = socket(AF_INET, SOCK_STREAM, AF_INET);
        mov rdi, AF_INET
        mov rsi, SOCK_STREAM
        mov rdx, 0
        mov rax, SOCKET
        syscall
        mov dword [sock_fd], eax

        ; Populate a
        mov word  [a + sockaddr_in.sin_family], AF_INET
        mov word  [a + sockaddr_in.sin_port], 0x5000
        mov dword [a + sockaddr_in.sin_addr], 0x0

        ; bind(socket_fd, &a, sizeof(a));
        mov r12, rax
        mov rdi, r12
        lea rsi, [a]
        mov rdx, sockaddr_in_size
        mov rax, BIND
        syscall

        ; listen(sock_fd, 0);
        mov rax, LISTEN
        mov edi, dword [sock_fd]
        mov rsi, 0
        syscall

parent_loop:

        ; conn_fd = accept(sock_fd, NULL, NULL);
        mov edi, dword [sock_fd] 
        xor rsi, rsi
        xor rdx, rdx
        mov rax, ACCEPT
        syscall
        mov dword [conn_fd], eax

        ; fork();
        mov rax, FORK
        syscall

        cmp rax, 0
        je child

        ; close(conn_fd);
        mov rdi, [conn_fd]
        mov rax, CLOSE
        syscall

        jmp parent_loop


child:
        ; close(sock_fd);
        mov rdi, [sock_fd]
        mov rax, CLOSE
        syscall

        ; read(conn_fd, buffer, sizeof(buffer-1));
        mov edi, dword [conn_fd]
        lea rsi, [buffer]
        mov rdx, BUFSIZE-1
        mov rax, READ
        syscall
        mov byte [buffer+rax], 0
        mov [req_size], rax

        ; Get file name from read request
        lea rdi, [buffer]
        mov rsi, 0x20 ; Space
        call strchr
        mov rdi, 1
        lea rdi, [rax+rdi]
        mov [filename], rdi
        mov rsi, 0x20 ; Space
        call strchr
        mov byte [rax], 0 ; Null terminate filename string
        mov qword [other_data], rax

        ; strncmp("... /... HTTP", "POST", 4);
        lea rdi, [buffer]
        lea rsi, [post_str]
        mov rdx, 4
        call strncmp
        cmp rax, 0
        je handle_POST

        ; strncmp("... /... HTTP", "GET", 3);
        lea rdi, [buffer]
        lea rsi, [get_str]
        mov rdx, 3
        call strncmp
        je handle_GET
        jmp exit

handle_POST:
        mov rdx, 511
        ; open(filename, O_CREAT|O_WRONLY);
        mov rdi, [filename]
        mov rsi, O_CREAT+O_WRONLY
        mov rax, OPEN
        syscall
        mov dword [file_fd], eax
        mov rax, [other_data]
        mov byte [rax], 0x20

        ; find(req, "\r\n\r\n");
        lea rdi, [buffer]
        lea rsi, [data_str] 
        call find
        add rax, 4
        mov r12, rax

        mov rdi, rax
        call strlen
        mov rdx, rax

        ; write(file_fd, "HTTP...", sizeof(response_str));
        mov edi, dword [file_fd]
        mov rsi, r12
        mov rax, WRITE
        syscall

        ; close(file_fd);
        mov edi, dword [file_fd]
        mov rax, CLOSE
        syscall

        ; write(conn_fd, "HTTP...", sizeof(response_str));
        mov edi, dword [conn_fd]
        lea rsi, [response]
        mov rdx, RESPSIZE 
        mov rax, WRITE
        syscall

        jmp exit


handle_GET:
        ; open(filename, O_RDONLY);
        mov rdi, [filename]
        mov rsi, O_RDONLY
        mov rax, OPEN
        syscall
        mov dword [file_fd], eax
        mov rax, [other_data]
        mov byte [rax], 0x20

        ; TODO: Add fstat syscall to get size of the file and 
        ; make a dynamic buffer based on it

        ; read(file_fd, buffer, sizeof(buffer-1));
        mov rdi, [file_fd]
        lea rsi, [buffer]
        mov rdx, BUFSIZE-1
        mov rax, READ
        syscall
        mov r12, rax

        ; close(file_fd);
        mov edi, dword [file_fd]
        mov rax, CLOSE
        syscall

        ; write(conn_fd, "HTTP...", sizeof(response_str));
        mov edi, dword [conn_fd]
        lea rsi, [response]
        mov rdx, RESPSIZE 
        mov rax, WRITE
        syscall

        ; write(conn_fd, buffer, file_sz);
        mov edi, dword [conn_fd]
        lea rsi, [buffer]
        mov rdx,  r12
        mov rax, WRITE
        syscall

        ; close(conn_fd);
        mov edi, dword [conn_fd]
        mov rax, CLOSE
        syscall

exit:
        ; exit(0);
        mov rdi, 0
        mov rax, EXIT
        syscall

; strchr(str1, char);
strchr:
        mov rax, 0
strchr_loop:
        cmp byte [rdi+rax], sil
        je strchr_finish
        inc rax
        jmp strchr_loop

strchr_finish:
        lea rax, [rdi+rax]
        ret


; strncmp(str1, str2, n);
strncmp:
        xor rax, rax
strncmp_loop:
        mov r9b, byte [rdi+rax]
        cmp r9b, byte [rsi+rax]
        jne strncmp_no_match
        cmp r9b, 0
        je strncmp_finish

        inc rax
        cmp rax, rdx
        je strncmp_finish ; numeric check

        jmp strncmp_loop
strncmp_no_match:
        mov rax, 1
        ret
strncmp_finish:
        mov rax, 0
        ret


;char* find(str, substr);
find:
find_loop:
        mov r9b, byte [rdi]
        cmp r9b, byte [rsi]
        je find_compare

        cmp r9b, 0
        je find_fail

        inc rdi
        jmp find_loop

find_compare
        mov rcx, rdi
        mov rdx, 4 ; TODO: make this useful universally
        call strncmp
        cmp rax, 0
        je find_success

        inc rdi
        jmp find_loop
find_success:
        mov rax, rcx
        ret

find_fail:
        mov rax, 0
        ret

strlen:
        mov rcx, 0
strlen_loop:
        cmp byte [rdi+rcx], 0
        je strlen_finish
        inc rcx
        jmp strlen_loop
strlen_finish:
        mov rax, rcx
        ret
