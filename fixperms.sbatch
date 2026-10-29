#!/bin/bash
#SBATCH --job-name=fixperms
#SBATCH --time=12:00:00
#SBATCH --mem=1G
#SBATCH --output=logs/changes/fixperms-%j.changes
#SBATCH --error=logs/progress/fixperms-%j.progress

bash ~/fix-permissions-hoffman2/fix-permissions-group-wide.sh -v /u/project/silvers/data silvers
