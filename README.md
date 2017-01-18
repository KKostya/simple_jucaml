# simple_jucaml
A very simple Jupyter kernel for OCaml

# Compilation
You'll need `Yojson`, `Nocrypto` and `ZMQ` bindings for OCaml.  It also relies
on `Core.Time` and `Core.Uuid` packages.

    opam install core
    opam install yojson
    opam install nocrypto
    opam install ZMQ

Native toplevel is not supported by OCaml, thus only bytecode compilation is possible.
    
    corebuild jucaml.byte

# Installation 
Check in which directories you can store kernels for Jupyter to find them.

    $ jupyter --paths
    config:
        /home/user/.jupyter
        /usr/etc/jupyter
        /usr/local/etc/jupyter
        /etc/jupyter
    data:
        /home/user/.local/share/jupyter
        /usr/local/share/jupyter
        /usr/share/jupyter
    runtime:
        /run/user/1000/jupyter

Pick one of them and make a `jucaml` subdirectory there.
    
    mkdir -p /home/user/.local/share/jupyter/kernels/jucaml

Finally, create a `kernel.json` with a path to the executable.

    cat > /home/user/.local/share/jupyter/kernels/jucaml/kernel.json << EOF
    {
        "argv": ["$PWD/jucaml.byte", "{connection_file}"],
        "display_name": "JUcaml",
        "language": "OCaml"
    }
    EOF
