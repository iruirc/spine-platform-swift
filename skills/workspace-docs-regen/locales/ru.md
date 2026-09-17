## description
Перегенерирует marker-секции в доках meta-repo и пакетов и файлы workspace из workspace.yml и исходников пакетов.

## report_regenerated_files
Перегенерировано {n} файл(ов).

## report_no_drift
Дрейфа нет; все marker-секции в каноническом виде.

## report_drift_detected
Обнаружен дрейф в {n} файл(ах):

## error_malformed_markers
В {n} файл(ах) сломаны маркеры; запусти с --repair, чтобы увидеть предлагаемое исправление. exit 2.

## error_validation
workspace.yml некорректен; ошибки перечислены выше. exit 2.

## error_yq_missing
yq не найден в PATH (нужен этому тулкиту). Установка: brew install yq

## error_missing_workspace_yml
workspace.yml не найден ни в этой папке, ни в её предках, ни в папке *-meta рядом с одним из них; перейди в любой репозиторий workspace'а.

## repair_prompt
Применить? (y/N)
