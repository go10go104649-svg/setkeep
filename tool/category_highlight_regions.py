"""Thumbnail-only surface regions in the relaxed mannequin's coordinates.

Anatomical reference: OpenStax Anatomy & Physiology 2e, section 11.5,
https://openstax.org/books/anatomy-and-physiology-2e/pages/11-5-muscles-of-the-pectoral-girdle-and-upper-limbs
These outlines are fitted to this model, not universal human measurements.
They do not change the Body tab's model, masks, or training scores.
"""
import math

# Right half, mirrored. Chest includes the inferior pectoral contour beneath
# the nipples. Deltoid caps the shoulder; upper arm starts below that cap and
# narrows toward the elbow. Forearm ends above the wrist, never on the hand.
REGIONS = {
    'chest': [
        [( .012,1.410),(.072,1.433),(.133,1.425),(.182,1.395),
         (.188,1.363),(.169,1.299),(.142,1.240),(.093,1.218),
         (.043,1.226),(.014,1.259)],
    ],
    'shoulders': [
        [(.135,1.439),(.177,1.462),(.229,1.449),(.263,1.415),
         (.271,1.366),(.252,1.322),(.232,1.300),(.212,1.335),
         (.196,1.377),(.172,1.412)],
    ],
    'arms': [
        [(.201,1.335),(.222,1.311),(.254,1.310),(.267,1.271),
         (.276,1.219),(.274,1.163),(.259,1.134),(.237,1.155),
         (.222,1.208),(.205,1.271)],
        [(.256,1.127),(.280,1.136),(.296,1.096),(.312,1.043),
         (.329,.998),(.323,.973),(.308,.988),(.283,1.030),
         (.262,1.074)],
    ],
}


def curve(points):
    result = []
    n = len(points)
    for i in range(n):
        a,b,c,d = [points[j % n] for j in (i-1,i,i+1,i+2)]
        for k in range(6):
            t = k / 6
            result.append(tuple(.5*((2*b[q])+(-a[q]+c[q])*t+
                (2*a[q]-5*b[q]+4*c[q]-d[q])*t*t+
                (-a[q]+3*b[q]-3*c[q]+d[q])*t*t*t) for q in (0,1)))
    return result

CURVES = {key: [curve(p) for p in polygons] for key,polygons in REGIONS.items()}


def weight_at(category, x, y, z):
    """Scalar reference for landmark regression tests."""
    x = abs(x)
    result = 0
    for polygon in CURVES[category]:
        inside, distance = False, float('inf')
        a = polygon[-1]
        for b in polygon:
            dx,dz = b[0]-a[0],b[1]-a[1]
            t = max(0,min(1,((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz)))
            distance = min(distance,math.hypot(x-a[0]-t*dx,z-a[1]-t*dz))
            if (a[1]>z)!=(b[1]>z) and x < dx*(z-a[1])/dz+a[0]:
                inside = not inside
            a = b
        result = max(result, 1 if inside else math.exp(-(distance/.005)**2))
    # Chest is anterior. Shoulder/arm wrap onto lateral surfaces naturally.
    if category == 'chest':
        result *= max(0,min(1,(-y-.005)/.025))
    return result


def surface_weights(category, positions):
    """Vectorized counterpart: smooth contour on the existing mesh surface."""
    import numpy as np
    x,y,z = np.abs(positions[:,0]),positions[:,1],positions[:,2]
    result = np.zeros(len(x),dtype=np.float32)
    for polygon in CURVES[category]:
        inside = np.zeros(len(x),dtype=bool)
        distance = np.full(len(x),np.inf)
        a = polygon[-1]
        for b in polygon:
            dx,dz = b[0]-a[0],b[1]-a[1]
            t = np.clip(((x-a[0])*dx+(z-a[1])*dz)/(dx*dx+dz*dz),0,1)
            distance = np.minimum(distance,(x-a[0]-t*dx)**2+(z-a[1]-t*dz)**2)
            if abs(dz)>1e-12:
                inside ^= ((a[1]>z)!=(b[1]>z)) & (x < dx*(z-a[1])/dz+a[0])
            a = b
        result = np.maximum(result,np.where(inside,1,np.exp(-distance/.005**2)))
    if category == 'chest':
        result *= np.clip((-y-.005)/.025,0,1)
    return result
