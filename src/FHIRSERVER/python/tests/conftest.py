import sys
import os

# Add the src directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), ".."))
# Add the src/python directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), "../../python"))
# Add the src/python/FhirInteraction directory to the path
sys.path.append(os.path.join(os.path.dirname(__file__), "../../python/FhirInteraction"))