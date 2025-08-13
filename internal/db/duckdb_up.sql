-- Enable and install sqlite extension
INSTALL sqlite;
LOAD sqlite;

-- Attach the macOS Screen Time SQLite database
ATTACH '{{ .HomeDir }}/Library/Application Support/Knowledge/knowledgeC.db' (TYPE sqlite);

-- For debugging, copy knowledgeC.db locally from the Library folder and switch the comment
--ATTACH '{{ .HomeDir }}/knowledgeC.db' (TYPE sqlite);

USE knowledgeC;
